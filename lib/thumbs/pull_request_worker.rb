require 'http'
require 'log4r'
module Thumbs
  class PullRequestWorker
    include Log4r
    include Thumbs::Slack
    attr_reader :build_dir
    attr_reader :build_status
    attr_reader :build_steps
    attr_reader :minimum_reviewers
    attr_reader :repo
    attr_reader :pr
    attr_reader :thumb_config
    attr_reader :log
    attr_reader :client


    def initialize(options)
      @repo = options[:repo]
      @client = Octokit::Client.new(:netrc => true)
      @pr = @client.pull_request(options[:repo], options[:pr])
      @build_dir=options[:build_dir] || "/tmp/thumbs/#{@repo.gsub(/\//, '_')}_#{@pr.number}"
      @build_status={:steps => {}}
      @build_steps = []
      try_read_config
      @minimum_reviewers = thumb_config && thumb_config.key?('minimum_reviewers') ? thumb_config['minimum_reviewers'] : 2
      @timeout=thumb_config && thumb_config.key?('timeout') ? thumb_config['timeout'] : 1800
    end

    def cleanup_build_dir
      FileUtils.rm_rf(@build_dir)
    end
    def try_read_config
      thumb_config_file="#{build_dir}/.thumbs.yml"
      if File.exist?(thumb_config_file)
        @thumb_config = YAML.load(IO.read(thumb_config_file))
      end
    end

    def refresh_repo
      if File.exists?(@build_dir) && Git.open(@build_dir).index.readable?
        `cd #{@build_dir} && git fetch`
      else
        clone
      end
    end
    def clone(dir=build_dir)
      status={}
      status[:started_at]=DateTime.now
      begin
        git = Git.clone("git@github.com:#{@repo}", dir)
      rescue => e
        status[:ended_at]=DateTime.now
        status[:result]=:error
        status[:message]="Clone failed!"
        status[:output]=e
        @build_status[:steps][:clone]=status
        raise StandardError
      end
      git
    end

    def try_merge
      pr_branch="feature_#{DateTime.now.strftime("%s")}"

      status={}
      status[:started_at]=DateTime.now
      cleanup_build_dir
      begin
        git = clone(@build_dir)
        git.checkout(@pr.head.sha)
        git.checkout(@pr.base.ref)
        git.branch(pr_branch).checkout
        debug_message "Trying merge #{@repo}:PR##{@pr.number} \" #{@pr.title}\" #{@pr.head.sha} onto #{@pr.base.ref}"
        merge_result = git.merge("#{@pr.head.sha}")
        load_thumbs_config
        status[:ended_at]=DateTime.now
        status[:result]=:ok
        status[:message]="Merge Success: #{@pr.head.sha} onto target branch: #{@pr.base.ref}"
        status[:output]=merge_result
      rescue => e
        log.error "Merge Failed"
        debug_message "PR ##{@pr[:number]} END"

        status[:result]=:error
        status[:message]="Merge test failed"
        status[:output]=e.inspect
      end

      @build_status[:steps][:merge]=status
      status
    end

    def try_run_build_step(name, command)
      status={}

      command = "cd #{@build_dir} && #{command} 2>&1"
      status[:started_at]=DateTime.now
      status[:command] = command
      begin
        Timeout::timeout(@timeout) do
          output = `#{command}`
          status[:ended_at]=DateTime.now
          unless $? == 0
            result = :error
            message = "Step #{name} Failed!"
          else
            result = :ok
            message = "OK"
          end
          status[:result] = result
          status[:message] = message

          status[:output] = output
          status[:exit_code] = $?.exitstatus

          @build_status[:steps][name.to_sym]=status
          debug_message "[ #{name.upcase} ] [#{result.upcase}] \"#{command}\""
          return status
        end
      rescue Timeout::Error => e
        status[:ended_at]=DateTime.now
        status[:result] = :error
        status[:message] = "Timeout reached (#{@timeout} seconds)"
        status[:output] = e

        @build_status[:steps][name.to_sym]=status
        debug_message "[ #{name.upcase} ] [ERROR] \"#{command}\" #{e}"
        return status
      end
    end

    def comments
      client.issue_comments(@repo, @pr.number)
    end

    def bot_comments
      comments.collect { |c| c if ["thumbot"].include?(c[:user][:login]) }.compact
    end

    def contains_plus_one?(comment_body)
      debug_message "match comment_body #{comment_body}"
     (/:\+1:/.match(comment_body) || /\+1/.match(comment_body) || /\\U0001F44D/.match(comment_body.to_yaml) ) ? true : false
    end

    def non_author_comments
      comments.collect { |comment| comment if @pr[:user][:login] != comment[:user][:login] && !["thumbot"].include?(comment[:user][:login]) }.compact
    end

    def org_member_comments
      org = @repo.split(/\//).shift
      non_author_comments.collect { |comment| comment if @client.organization_member?(org, comment[:user][:login])}.compact
    end

    def org_member_code_reviews
      org_member_comments.collect { |comment| comment if contains_plus_one?(comment[:body]) }.compact
    end
    def code_reviews
      non_author_comments.collect { |comment| comment if contains_plus_one?(comment[:body]) }.compact
    end

    def review_count
      reviews.collect{|r| r[:user][:login] }.uniq.length
    end
    def reviews
      debug_message "calculating reviews"
      debug_message "comments: #{comments.collect{|mc| mc[:user][:login]}}"
      debug_message "bot_comments: #{bot_comments.collect{|mc| mc[:user][:login]}}"
      debug_message "org_member_comments: #{org_member_comments.collect{|mc| mc[:user][:login]}}"
      debug_message "org_member_code_reviews: #{org_member_code_reviews.collect{|mc| mc[:user][:login] }}"
      debug_message "non_org_member_code_reviews: #{code_reviews.collect{|mc| mc[:user][:login] }}"
      debug_message "non_org_member_code_reviews: #{code_reviews.collect{|mc| mc[:user][:login] }}"

       if @thumb_config['org_mode']
         debug_message "returning org_member_code_reviews"
         return org_member_code_reviews
       end

      code_reviews
    end

    def debug_message(message)
      $logger.respond_to?(:debug) ? $logger.debug("#{@repo} #{@pr.number} #{@pr.state} #{message}") : ""
    end
    def error_message(message)
      $logger.respond_to?(:error) ? $logger.error("#{message}") : ""
    end
    def valid_for_merge?
      debug_message "determine valid_for_merge?"
      unless state == "open"
        debug_message "#valid_for_merge?  state != open"
        return false
      end
      unless mergeable?
        debug_message "#valid_for_merge? != mergeable? "
        return false
      end
      unless mergeable_state == "clean"
        debug_message "#valid_for_merge? mergeable_state != clean #{mergeable_state} "
        return false
      end

      return false unless @build_status.key?(:steps)
      return false unless @build_status[:steps].key?(:merge)

      debug_message "passed initial"
      debug_message("")
      @build_status[:steps].each_key do |name|
        unless @build_status[:steps][name].key?(:result)
          return false
        end
        unless @build_status[:steps][name][:result]==:ok
          debug_message "result not :ok, not valid for merge"
          return false
        end
      end
      debug_message "all keys and result ok present"

      unless @thumb_config
        debug_message "config missing"
        return false
      end
      unless @thumb_config.key?('minimum_reviewers')
        debug_message "minimum_reviewers config option missing"
        return false
      end
      debug_message "minimum reviewers: #{thumb_config['minimum_reviewers']}"
      debug_message "review_count: #{review_count} >= #{thumb_config['minimum_reviewers']}"

      unless review_count >= @thumb_config['minimum_reviewers']
        debug_message " #{review_count} !>= #{@thumb_config['minimum_reviewers']}"
        message="#{review_count} Code reviews, waiting for #{minimum_reviewers}" + (thumb_config['org_mode'] ? " from organization #{repo.split(/\//).shift}." : ".")
        add_comment(message)
        return false
      end

      unless @thumb_config['merge'] == true
        debug_message "thumb_config['merge'] != 'true' || thumbs config says: merge: #{thumb_config['merge'].inspect}"
        add_comment "No Automerge:  *.thumbs.yml* says ```merge: #{thumb_config['merge'].inspect}```"
        return false
      end
      debug_message "valid_for_merge? TRUE"
      return true
    end

    def validate
      cleanup_build_dir
      clone
      try_merge

      # before_steps.each do |before_step|
      #   run_before_step(before_step)
      # end
      #
      build_steps.each do |build_step|
        build_step_name=build_step.gsub(/\s+/, '_').gsub(/-/, '')
        try_run_build_step(build_step_name, build_step)
      end
    end

    def merge
      status={}
      status[:started_at]=DateTime.now
      if merged?
        debug_message "already merged ? nothing to do here"
        status[:result]=:error
        status[:message]="already merged"
        status[:ended_at]=DateTime.now
        return status
      end
      unless state == "open"
        debug_message "pr not open"
        status[:result]=:error
        status[:message]="pr not open"
        status[:ended_at]=DateTime.now
        return status
      end
      unless mergeable?
        debug_message "no mergeable? nothing to do here"
        status[:result]=:error
        status[:message]=".mergeable returns false"
        status[:ended_at]=DateTime.now
        return status
      end
      unless mergeable_state == "clean"

        debug_message ".mergeable_state not clean! "
        status[:result]=:error
        status[:message]=".mergeable_state not clean"
        status[:ended_at]=DateTime.now
        return status
      end

      # validate config
      unless thumb_config && thumb_config.key?('build_steps') && thumb_config.key?('minimum_reviewers')
        debug_message "no usable .thumbs.yml"
        status[:result]=:error
        status[:message]="no usable .thumbs.yml"
        status[:ended_at]=DateTime.now
        return status
      end
      unless thumb_config.key?('minimum_reviewers')
        debug_message "no minimum reviewers configured"
        status[:result]=:error
        status[:message]="no minimum reviewers configured"
        status[:ended_at]=DateTime.now
        return status
      end

      if thumb_config.key?('merge') == 'false'
        debug_message ".thumbs.yml config says no merge"
        status[:result]=:error
        status[:message]=".thumbs.yml config merge=false"
        status[:ended_at]=DateTime.now
        return status
      end

      begin
        debug_message("Starting github API merge request")
        commit_message = 'Thumbs Git Robot Merge. '

        merge_response = client.merge_pull_request(@repo, @pr.number, commit_message, options = {})
        merge_comment="Successfully merged *#{@repo}/pulls/#{@pr.number}* (*#{@pr.head.sha}* on to *#{@pr.base.ref}*)\n\n"
        merge_comment << " ```yaml    \n#{merge_response.to_hash.to_yaml}\n ``` \n"

        add_comment merge_comment
        debug_message "Merge OK"
      rescue StandardError => e
        log_message = "Merge FAILED #{e.inspect}"
        debug_message log_message

        status[:message] = log_message
        status[:output]=e.inspect
      end
      status[:ended_at]=DateTime.now

      debug_message "Merge #END"
      status
    end

    def mergeable?
      client.pull_request(@repo, @pr.number).mergeable
    end

    def mergeable_state
      client.pull_request(@repo, @pr.number).mergeable_state
    end

    def merged?
      client.pull_merged?(@repo, @pr.number)
    end

    def state
      client.pull_request(@repo, @pr.number).state
    end

    def open?
      debug_message "open?"
      client.pull_request(@repo, @pr.number).state == "open"
    end

    def add_comment(comment)
      client.add_comment(@repo, @pr.number, comment, options = {})
    end

    def close
      client.close_pull_request(@repo, @pr.number)
    end

    def build_status_problem_steps
      @build_status[:steps].collect { |step_name, status| step_name if status[:result] != :ok }.compact
    end

    def aggregate_build_status_result
      @build_status[:steps].each { |step_name, status| return :error unless status[:result] == :ok }
      :ok
    end

    def create_build_status_comment
      if aggregate_build_status_result == :ok
        @status_title="Looks good!  :+1:"
      else
        @status_title="Looks like there's an issue with build step #{build_status_problem_steps.join(",")} !  :cloud: "
      end

      comment = render_template <<-EOS
<p>Build Status: <%= @status_title %></p>
<% @build_status[:steps].each do |step_name, status| %>
<% if status[:output] %>
<% gist=client.create_gist( { :files => { step_name.to_s + ".txt" => { :content => status[:output] }} }) %>
<% end %>
<details>
 <summary><%= result_image(status[:result]) %> <%= step_name.upcase %> </summary>

 <p>

> Started at: <%= status[:started_at].strftime("%Y-%m-%d %H:%M") rescue nil%>
> Duration: <%= status[:ended_at].strftime("%s").to_i-status[:started_at].strftime("%s").to_i rescue nil %> seconds.
> Result:  <%= status[:result].upcase %>
> Message: <%= status[:message] %>
> Exit Code:  <%= status[:exit_code] || status[:result].upcase %>
> <a href="<%= gist.html_url %>">:page_facing_up:</a>
</p>

```

<%= status[:command] %>

<%= status[:output] %>

```

--------------------------------------------------

</details>

<% end %>
<% status_code= (review_count >= minimum_reviewers ? :ok : :unchecked) %>
<% org_msg=  thumb_config['org_mode'] ? " from organization #{repo.split(/\//).shift}"  : "." %>
<details>
 <summary><%= result_image(status_code) %> <%= review_count %> of <%= minimum_reviewers %> Code reviews<%= org_msg %></summary>

<p>
<% reviews.each do |review| %>

  @<%= review[:user][:login] %>: <%= review[:body] %> 

<% end %>
</p>
</details>
      EOS
      add_comment(comment)
    end

    def create_reviewers_comment
      comment = render_template <<-EOS
<% reviewers=reviews.collect { |r| "*@" + r[:user][:login] + "*" } %>
Code reviews from: <%= reviewers.uniq.join(", ") %>.
      EOS
      add_comment(comment)
    end

    private

    def render_template(template)
      ERB.new(template).result(binding)
    end

    def authenticate_github
      Octokit.configure do |c|
        c.login = ENV['GITHUB_USER']
        c.password = ENV['GITHUB_PASS']
      end
    end

    def load_thumbs_config
      thumb_file = File.join(@build_dir, ".thumbs.yml")
      unless File.exist?(thumb_file)
        debug_message "\".thumbs.yml\" config file not found"
        return false
      end
      begin
        @thumb_config=YAML.load(IO.read(thumb_file))
        @build_steps=@thumb_config['build_steps']
        @minimum_reviewers=@thumb_config['minimum_reviewers']
        @auto_merge=@thumb_config['merge']
        @timeout=@thumb_config['timeout']
        debug_message "\".thumbs.yml\" config file Loaded: #{@thumb_config.to_yaml}"
      rescue => e
        error_message "thumbs config file loading failed"
        return nil
      end
      @thumb_config
    end

    def result_image(result)
      case result
        when :ok
          ":white_check_mark:"
        when :warning
          ":warning:"
        when :unchecked
          ":white_large_square:"
        when :error
          ":no_entry:"
        else
          ""
      end
    end
  end
end
