module Thumbs
  class PullRequestWorker
    attr_reader :build_dir
    attr_reader :repo
    attr_reader :pr
    attr_reader :log
    attr_reader :org
    attr_reader :thumbs_config_default

    def initialize(options)
      if options[:url]
        @repo, @pr = parse_github_pr_url(options[:url])
      end
      @repo ||= options[:repo]
      @org = @repo.split('/').first
      @pr ||= options[:pr]
      @build_dir = options[:build_dir] || "/tmp/thumbs/#{build_guid}"
      @thumbs_config_default = options[:thumbs_config_default]

      prepare_build_dir
    end

    def reset_state
      @pull_request =
      @event =
      @open_pull_requests =
      @commits =
      @base_commits =
      @head_commits =
      @comments_since_most_recent_commit =
      nil
    end

    def octokit_client
      @octokit_client ||= Octokit::Client.new(:netrc => true)
    end

    def pull_request
      @pull_request ||= octokit_client.pull_request(repo, pr)
    end

    def reset_build_status
      @build_status = {:steps => {}}
    end

    def build_status
      return @build_status if @build_status
      persisted_build_status = read_build_status
      @build_status = persisted_build_status || {:steps => {}}
    end

    def prepare_build_dir
      return if @prepared_bulid_dir
      refresh_repo
      res = try_merge
      @prepared_bulid_dir = true
      res
    end

    def refresh_repo
      debug_message "refreshing repo"
      if File.exists?(build_dir) && Git.open(build_dir).index.readable?
        git = Git.open(build_dir)
        git.fetch
        debug_message "fetch"
        git
      else
        debug_message "clone"
        clone
      end
    end

    def clone()
      dir = build_dir
      status = {}
      status[:started_at] = DateTime.now
      begin
        git = Git.clone("git@github.com:#{pull_request.base.repo.full_name}", dir)
      rescue => e
        status[:ended_at] = DateTime.now
        status[:result] = :error
        status[:message] = "Clone failed!"
        status[:output] = e
        build_status[:steps][:clone] = status
        return status
      end
      git
    end

    def try_merge
      pr_branch = "feature_#{DateTime.now.strftime("%s")}"

      status = {}
      status[:started_at] = DateTime.now

      debug_message "Trying merge #{pull_request.base.repo.full_name}:PR##{pull_request.number} \" #{pull_request.title}\" #{pull_request.head.repo.full_name}##{most_recent_head_sha} onto #{pull_request.base.ref} #{most_recent_base_sha}"
      begin
        git = refresh_repo
        git.reset
        git.checkout(pull_request.base.ref)
        git.branch(pr_branch).checkout
        debug_message "Trying merge #{repo}:PR##{pull_request.number} \" #{pull_request.title}\" #{most_recent_head_sha} onto #{pull_request.base.ref} #{most_recent_base_sha}"

        if forked_repo_branch_pr?
          contributor_repo = "git://github.com/#{pull_request.head.repo.full_name}"
          debug_message("Forked branch pr contributor REPO: #{contributor_repo}")
          unless git.remotes.any? { |r| r.name == 'contributor' }
            git.add_remote("contributor", contributor_repo)
          end
          git.fetch("contributor")
          merge_result = git.remote("contributor").merge(pull_request.head.ref)
        else
          merge_result = git.merge(most_recent_head_sha)
        end

        status[:ended_at] = DateTime.now
        status[:result] = :ok
        status[:message] = "Merge Success: #{pull_request.head.ref} #{most_recent_head_sha} onto target branch: #{pull_request.base.ref} #{most_recent_base_sha}"
        status[:output] = "#{merge_result}"
      rescue => e
        debug_message "Merge Failed: #{pull_request.head.ref} #{most_recent_head_sha} onto target branch: #{pull_request.base.ref} #{most_recent_base_sha}"
        debug_message "PR ##{pull_request[:number]} END"

        status[:result] = :error
        status[:message] = "Merge Failed: #{pull_request.head.ref} #{most_recent_head_sha} onto target branch: #{pull_request.base.ref} #{most_recent_base_sha}"
        status[:output] = e.inspect
      end

      build_status[:steps][:merge] = status
      status
    end

    def run_command_in_docker(command)
      image = config_docker_image
      shell = config_shell
      command = "source /etc/bash.bashrc; #{command}"
      docker_command = "sudo docker run -t"
      (config_env).each do |variable_key, variable_value|
        docker_command << " -e #{variable_key}=#{variable_value}"
      end
      docker_command << " -v ~/.bashrc:/etc/bash.bashrc -v /tmp/thumbs:/tmp/thumbs"
      docker_command << " #{image} #{shell} -c '#{command}'"

      debug_message docker_command
      output, exit_code = run_command_in_shell(docker_command)
      [output, exit_code]
    end

    def run_command_in_shell(command)
      shell = config_shell

      output, exit_code = nil

      Open3.popen2e(ENV, shell) do |stdin, stdout_and_stderr, wait_thr|
        stdin.puts "source ~/.bashrc"
        stdin.puts "#{command} 2>&1"
        stdin.close
        wait_thr.pid
        output = stdout_and_stderr.read
        exit_code = wait_thr.value.exitstatus
      end
      [output, exit_code]
    end

    def run_command(command)
      if config_docker?
        run_command_in_docker(command)
      else
        run_command_in_shell(command)
      end
    end

    def try_run_build_step(name, command)
      status = {}

      command = "cd #{build_dir}; #{command}"

      debug_message "running command #{command}"

      status[:started_at] = DateTime.now
      status[:command] = command
      status[:env] = config_env

      status[:env].each do |key, value|
        ENV[key] = "#{value}"
      end
      begin
        Timeout::timeout(config_timeout) do
          output, exit_code = run_command(command)
          unless output && output.strip != ""
            output = "No output"
          end
          status[:ended_at] = DateTime.now
          unless exit_code == 0
            result = :error
            message = "Step #{name} Failed!"
          else
            result = :ok
            message = "OK"
          end
          status[:result] = result
          status[:message] = message

          status[:output] = sanitize_text(output)
          status[:exit_code] = exit_code.to_i

          build_status[:steps][name.to_sym] = status
          debug_message "[ #{name.upcase} ] [#{result.upcase}] \"#{command}\""
          return status
        end

      rescue Timeout::Error => e
        status[:ended_at] = DateTime.now
        status[:result] = :error
        status[:message] = "Timeout reached (#{config_timeout} seconds)"
        status[:output] = e

        build_status[:steps][name.to_sym] = status
        debug_message "[ #{name.upcase} ] [ERROR] \"#{command}\" #{e}"
        return status
      end
    end

    def events
      @events ||= octokit_client.repository_events(repo).collect { |e| e.to_h }
    end

    def push_timestamp(sha)
      push_event = events.detect { |e| e[:payload][:head] == sha &&
                                  e[:type] == 'PushEvent' }
      timestamp = event_timestamp(push_event)
      timestamp || pull_request.created_at
    end

    def to_timestamp(value)
      DateTime.parse(value.to_s)
    end

    def event_timestamp(event)
      return unless event
      to_timestamp(event[:created_at])
    end

    def comment_timestamp(comment)
      to_timestamp(comment[:created_at])
    end

    def comments_since_most_recent_commit
        @comments_since_most_recent_commit ||=
        all_comments.compact.select { |c|
          config_comments_since_disabled? ||
          comment_timestamp(c) > most_recent_commit_timestamp
        }.map { |c| c.to_h }.compact
    end

    def all_comments
      # TODO: allow for paging over all_comments
      octokit_client.issue_comments(repo, pull_request.number, per_page: 100)
    end

    def comments
      comments_since_most_recent_commit
    end

    def bot_comments
      comments.collect { |c| c if ["thumbot"].include?(c[:user][:login]) }.compact
    end

    def contains_plus_one?(comment_body)
      (/:\+1:/.match(comment_body) || /\+1/.match(comment_body) || /\\U0001F44D/.match(comment_body.to_yaml)) ? true : false
    end

    def non_author_comments
      comments.select { |comment| pull_request[:user][:login] != comment[:user][:login] &&
                        !["thumbot"].include?(comment[:user][:login]) }.compact
    end

    def repo_is_org?
      return @repo_is_org if @repo_is_org
      begin
        org_result = octokit_client.organization(org)
      rescue  Octokit::NotFound
        return false
      end
      @repo_is_org = org_result && org_result.key?(:id) ? true : false
    end

    def org_member?(user_login)
      @org_members ||= {}
      @org_members[user_login] ||=
          octokit_client.organization_member?(org, user_login)
    end

    def org_member_comments
      non_author_comments.collect { |comment| comment if org_member?(comment[:user][:login]) }.compact
    end

    def org_member_code_reviews
      org_member_comments.collect { |comment| comment if contains_plus_one?(comment[:body]) }.compact
    end

    def code_reviews
      non_author_comments.collect { |comment| comment if contains_plus_one?(comment[:body]) }.compact
    end

    def review_count
      approval_logins = approvals.collect { |a| a["author"]["login"] }.uniq
      comment_code_approval_logins = comment_code_approvals.collect { |r| r[:user][:login] }.uniq
      countable_reviews = (approval_logins + comment_code_approval_logins).uniq
      countable_reviews.length
    end

    def logger
      @logger ||= Log4r::Logger['Thumbs']
    end

    def debug_message(message)
      logger && logger.respond_to?(:debug) &&
          logger.debug("#{repo} #{pull_request.number} #{pull_request.state} #{message}")
    end

    def error_message(message)
      logger && logger.respond_to?(:error) &&
          logger.error("#{message}")
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

      unless build_status.key?(:steps)
        debug_message "contains no steps"
        return false
      end
      unless build_status[:steps].key?(:merge)
        debug_message "contains no merge step"
        return false
      end
      unless build_status[:steps].keys.length > 1
        debug_message "contains no build steps #{build_status[:steps]}"
        return false
      end
      debug_message "passed initial"
      debug_message("")
      build_status[:steps].each_key do |name|
        unless build_status[:steps][name].key?(:result)
          return false
        end
        unless build_status[:steps][name][:result] == :ok
          debug_message "result not :ok, not valid for merge"
          return false
        end
      end
      debug_message "all keys and result ok present"

      unless thumbs_config_present?
        debug_message "config missing"
        return false
      end
      unless config_minimum_reviewers_present?
        debug_message "minimum_reviewers config option missing"
        return false
      end
      review_count_value = review_count
      debug_message "minimum reviewers: #{config_minimum_reviewers}"
      debug_message "review_count: #{review_count_value} >= #{config_minimum_reviewers}"

      unless review_count_value >= config_minimum_reviewers
        debug_message " #{review_count_value} !>= #{config_minimum_reviewers}"
        return false
      end

      if wait_lock?
        debug_message "wait_lock? thumbot wait set. delete comment to release lock"
        return false
      end

      unless config_auto_merge?
        debug_message "thumb_config['merge'] != 'true' || thumbs config says: merge: #{thumb_config['merge'].inspect}"
        return false
      end
      debug_message "valid_for_merge? TRUE"
      return true
    end

    def build_in_progress?
      [:in_progress, :completed].include?(build_progress_status)
    end

    def build_progress_status
      build_progress_comment = get_build_progress_comment
      debug_message "got build_progress_comment #{build_progress_comment}"
      return :unstarted unless build_progress_comment
      return :unstarted unless build_progress_comment.kind_of?(Hash) && build_progress_comment.key?(:body)
      return :unstarted unless build_progress_comment[:body].length > 0

      progress_status_line = build_progress_comment[:body].lines[2]
      progress_status = progress_status_line.split(/\|/).pop.split(/\s+/).pop

      unless progress_status
        debug_message "invalid"
        return :unstarted
      end

      progress_status = progress_status.strip.to_sym

      ([:in_progress, :completed].include?(progress_status) ? progress_status : :unstarted)
    end

    def build_guid
      "#{pull_request.base.ref.gsub(/\//, '_')}.#{most_recent_base_sha.slice(0, 7)}.#{pull_request.head.ref.gsub(/\//, '_')}.#{most_recent_head_sha.slice(0, 7)}"
    end

    def set_build_progress(progress_status)
      update_or_create_build_status(most_recent_head_sha, progress_status)
    end

    def compose_build_status_comment_title(progress_status)
      status_emoji = (progress_status == :completed ? result_image(aggregate_build_status_result) : result_image(progress_status))
      comment_title = "|||||\n"
      comment_title << "------------ | -------------|------------ | ------------- \n"
      comment_title << "#{pull_request.head.ref} #{most_recent_head_sha.slice(0, 7)} | :arrow_right: | #{pull_request.base.ref} #{most_recent_base_sha.slice(0, 7)} | #{status_emoji} #{progress_status}"
      comment_title
    end

    def set_build_status_comment(sha, status)
      #final check that sha comment doesnt already exist
      comment = get_build_progress_comment
      unless comment.key?(:id)
        add_comment(compose_build_status_comment_title(status))
      end
    end

    def get_build_progress_comment
      bot_comments.detect { |c|
        c[:body].lines.length > 1 &&
        c[:body].lines[2] =~ /^#{pull_request.head.ref} #{most_recent_head_sha.slice(0, 7)} \| :arrow_right: \| #{pull_request.base.ref} #{most_recent_base_sha.slice(0, 7)}/
      } || {:body => ""}
    end

    def update_or_create_build_status(sha, progress_status)
      if build_progress_status == :unstarted
        set_build_status_comment(sha, progress_status)
      else
        comment = get_build_progress_comment
        comment_id = comment[:id]
        debug_message "comment id is #{comment_id}"
        comment_message = compose_build_status_comment_title(progress_status)
        debug_message comment_message
        update_pull_request_comment(comment_id, comment_message)
      end
    end

    def update_pull_request_comment(comment_id, comment_message)
      begin
        comment = octokit_client.issue_comment(repo, comment_id)
        unless comment && comment.key?(:id)
          debug_message "comment doesnt exist"
          return nil
        end
      rescue Octokit::NotFound
        debug_message "comment doesnt exist"
        return nil
      end
      octokit_client.update_comment(repo, comment[:id], comment_message)
    end

    def sanitize_text(text)
      text.to_s.encode('UTF-8', 'UTF-8', :invalid => :replace, :undef => :replace)
    end

    def create_gist_from_status(name, content)
      file_title = "#{name.to_s.gsub(/\//, '_')}.txt"
      octokit_client.create_gist({:files => {file_title => {:content => content || "no output"}}})
    end

    def clear_build_progress_comment
      build_progress_comment = get_build_progress_comment
      build_progress_comment ? octokit_client.delete_comment(repo, build_progress_comment[:id]) : true
    end

    def pushes
      events.collect { |e| e if e[:type] == 'PushEvent' }.compact
    end

    def most_recent_sha
      most_recent_head_sha
    end

    def run_build_steps
      debug_message "begin run_build_steps"
      config_build_steps.each do |build_step|
        build_step_name = build_step.gsub(/\s+/, '_').gsub(/-/, '')
        debug_message "run build step #{build_step_name} begin"
        try_run_build_step(build_step_name, build_step)
        debug_message "run build step #{build_step_name} end"
        persist_build_status
        debug_message "run build step #{build_step_name} persist"
      end
    end

    def sanitized_repo
      @sanitized_repo ||= repo.gsub(/\//, '_')
    end

    def sanitized_build_file
      return @sanitized_build_file if @sanitized_build_file
      FileUtils.mkdir_p('/tmp/thumbs')
      @sanitized_build_file =
        File.join('/tmp/thumbs', "#{sanitized_repo}_#{build_guid}.yml")
    end

    def persist_build_status
      build_status[:steps].keys.each do |build_step|
        next unless build_status[:steps][build_step].key?(:output)
        output = build_status[:steps][build_step][:output]
        build_status[:steps][build_step][:output] = sanitize_text(output)
      end
      File.open(sanitized_build_file, "w") do |f|
        f.syswrite(build_status.to_yaml)
      end
      true
    end

    def unpersist_build_status
      File.delete(sanitized_build_file) if File.exist?(sanitized_build_file)
    end

    def read_build_status
      if File.exist?(sanitized_build_file)
        begin
          YAML.load(IO.read(sanitized_build_file))
        rescue Psych::SyntaxError
        end
      else
        {:steps => {}}
      end
    end

    def validate
      build_status = read_build_status

      if build_status.key?(:steps) && build_status[:steps].keys.length > 1
        debug_message "using persisted build status cause #{build_status.key?(:steps)} && #{build_status[:steps].keys.length} #{build_status[:steps].to_yaml}"
      else
        refresh_repo
        debug_message "no build status found, running build steps"
        try_merge
        run_build_steps
      end
    end

    def merge
      status = {}
      status[:started_at] = DateTime.now
      if merged?
        debug_message "already merged ? nothing to do here"
        status[:result] = :error
        status[:message] = "already merged"
        status[:ended_at] = DateTime.now
        return status
      end
      unless state == "open"
        debug_message "pr not open"
        status[:result] = :error
        status[:message] = "pr not open"
        status[:ended_at] = DateTime.now
        return status
      end
      unless mergeable?
        debug_message "no mergeable? nothing to do here"
        status[:result] = :error
        status[:message] = ".mergeable returns false"
        status[:ended_at] = DateTime.now
        return status
      end
      unless mergeable_state == "clean"
        debug_message ".mergeable_state not clean! "
        status[:result] = :error
        status[:message] = ".mergeable_state not clean"
        status[:ended_at] = DateTime.now
        return status
      end

      # validate config
      unless config_build_steps_present? && config_minimum_reviewers_present?
        debug_message "no usable .thumbs.yml"
        status[:result] = :error
        status[:message] = "no usable .thumbs.yml"
        status[:ended_at] = DateTime.now
        return status
      end

      unless config_auto_merge?
        debug_message ".thumbs.yml config says no merge"
        status[:result] = :error
        status[:message] = ".thumbs.yml config merge=false"
        status[:ended_at] = DateTime.now
        return status
      end

      if wait_lock?
        debug_message "wait_lock? thumbot wait enabled."
        status[:result] = :error
        status[:message] = "wait_lock? thumbot wait enabled."
        status[:ended_at] = DateTime.now
        return status
      end

      begin
        debug_message("Starting github API merge request")
        commit_message = 'Thumbs Git Robot Merge. '

        octokit_client.merge_pull_request(repo, pull_request.number, commit_message, options: {})
        merge_comment = "Successfully merged *#{repo}/pulls/#{pull_request.number}* (*#{most_recent_head_sha}* on to *#{pull_request.base.ref}*)\n\n"
        merge_comment << " ```yaml    \n#{merge_response.to_hash.to_yaml}\n ``` \n"

        add_comment merge_comment
        debug_message "Merge OK"
      rescue StandardError => e
        log_message = "Merge FAILED #{e.inspect}"
        debug_message log_message

        status[:message] = log_message
        status[:output] = e.inspect
      end
      status[:ended_at] = DateTime.now

      debug_message "Merge #END"
      status
    end

    def mergeable?
      pull_request.mergeable
    end

    def mergeable_state
      pull_request.mergeable_state
    end

    def merged?
      octokit_client.pull_merged?(repo, pull_request.number)
    end

    def state
      pull_request.state
    end

    def open?
      state == "open"
    end

    def add_comment(comment, options = {})
      octokit_client.add_comment(repo, pull_request.number, comment, options = {})
    end

    def close
      octokit_client.close_pull_request(repo, pull_request.number)
    end

    def open_pull_requests
      @open_pull_requests ||= octokit_client.pull_requests(repo, :state => 'open')
    end

    def commits
      @commits ||= octokit_client.commits(pull_request.head.repo.full_name, pull_request.head.ref)
    end

    def base_commits
      @base_commits ||= octokit_client.commits(pull_request.base.repo.full_name, pull_request.base.ref)
    end

    def most_recent_head_sha
      commits.first[:sha]
    end

    def most_recent_base_sha
      base_commits.first[:sha]
    end

    def pull_requests_for_base_branch(branch)
      open_pull_requests.select { |pr| pr.base.ref == branch }
    end

    def build_status_problem_steps
      build_status[:steps].collect { |step_name, status| step_name if status[:result] != :ok }.compact
    end

    def aggregate_build_status_result
      build_status[:steps].each do |step_name, status|
        unless status.kind_of?(Hash) && status.key?(:result) && status[:result] == :ok
          debug_message "error: "
          debug_message status.to_yaml
          return :error
        end
      end
      :ok
    end

    def status_title
      if aggregate_build_status_result == :ok
        "\n<details><Summary>Looks good!  :+1: </Summary>"
      else
        "\n<details><Summary>There seems to be an issue with build step **#{build_status_problem_steps.join(",")}** !  :cloud: </Summary>"
      end
    end

    def create_build_status_comment
      build_comment = render_template <<-EOS
<% build_status[:steps].each do |step_name, status| %>
<% if status[:output] %>
<% gist = create_gist_from_status(step_name, status[:output]) %>
<% end %>
<details>
 <summary><%= result_image(status[:result]) %> <%= step_name.upcase %> </summary>

 <p>

> Started at: <%= status[:started_at].strftime("%Y-%m-%d %H:%M") rescue nil%>
> Duration: <%= status[:ended_at].strftime("%s").to_i-status[:started_at].strftime("%s").to_i rescue nil %> seconds.
> Result:  <%= status[:result].upcase %>
> Message: <%= status[:message] %>
> Exit Code:  <%= status[:exit_code] || status[:result].upcase %>
<% if gist.respond_to?(:html_url) %>
> <a href="<%= gist.html_url %>">:page_facing_up:</a>
<% end %>
</p>

```

<%= status[:command] %>

<% output = status[:output] %>
<% allowed_length = 10000 %>
<% if output.length > allowed_length %>
  <% snipped_characters = output.length - allowed_length %>
  <% snipped_lines = output.slice(0, output.length-allowed_length).split(/\n/) %>
... Snipped <%= snipped_lines.length %> lines ...
<%= output.slice(output.length-allowed_length, output.length) %>
<% else %>
  <%= output %>
<% end %>


```

--------------------------------------------------

</details>

<% end %>
<%= render_reviewers_comment_template if thumbs_config_present? %>

</details>
      EOS
      comment_id = get_build_progress_comment[:id]
      comment_message = compose_build_status_comment_title(:completed)
      comment_message << "\n#{status_title}"
      comment_message << build_comment
      if comment_message.length > 65000
        debug_message "comment_message too large : #{comment_message.length} unable to post"
      else
        update_pull_request_comment(comment_id, comment_message)
      end
    end

    def render_reviewers_comment_template
      render_template <<-EOS
<% status_code = (review_count >= config_minimum_reviewers ? :ok : :unchecked) %>
<% org_msg = config_org_mode ? " from organization #{repo.split(/\//).shift}"  : "." %>
<details>
<summary><%= result_image(status_code) %> <%= review_count %> of <%= config_minimum_reviewers %> Code reviews<%= org_msg %></summary>
<% effective_approvals.each do |review| %>
  <% if review.key?(:user) && review[:user].key?(:login) %>
  - @<%= review[:user][:login] %>: <%= review[:body] %> 
  <% end %>
  <% if review.key?("author") && review["author"].key?("login") %>
  - @<%= review["author"]["login"] %>:  <% review["body"] %>
  <% end %>
<% end %>
</details>
EOS
    end

    def create_reviewers_comment
      comment = render_reviewers_comment_template
      add_comment(comment)
    end

    def thumbs_config_path
      File.join(build_dir, ".thumbs.yml")
    end

    def thumbs_config
      return @thumbs_config if @thumbs_config
      unless thumbs_config_present?
        debug_message "\".thumbs.yml\" config file not found"
        return thumbs_config_default
      end
      begin
        @thumbs_config = YAML.load(IO.read(thumbs_config_path))
        debug_message "\".thumbs.yml\" config file Loaded: #{thumbs_config.to_yaml}"
      rescue
        error_message "thumbs config file loading failed"
        return thumbs_config_default
      end
      @thumbs_config
    end
 
    def thumbs_config_present?
      File.exist?(thumbs_config_path)
    end

    def config_value(key, default = nil)
      config = thumbs_config
      config && config[key] || default
    end

    def config_value_set(key, value)
      config = thumbs_config
      config && config[key] = value
    end

    def config_key_present?(key)
      config = thumbs_config
      config && config.key?(key)
    end

    def config_build_steps
      config_value('build_steps',  [])
    end

    def config_build_steps_present?
      config_key_present?('build_steps')
    end

    def config_minimum_reviewers
      config_value('minimum_reviewers', 2)
    end
 
    def config_minimum_reviewers_set(value)
      config_value_set('minimum_reviewers', value)
    end

    def config_minimum_reviewers_present?
      config_key_present?('minimum_reviewers')
    end

    def config_auto_merge_set(value)
      config_value_set('merge', value)
    end

    def config_auto_merge?
      config_value('merge', false)
    end

    def config_auto_merge_present?
      config_key_present?('merge')
    end

    def config_timeout
      config_value('timeout', 1800)
    end

    def config_org_mode
      config_value('org_mode', true)
    end

    def config_docker_image
      config_value('docker_image', 'ubuntu')
    end

    def config_shell
      config_value('shell', '/bin/bash')
    end

    def config_env
      config_value('env', {})
    end

    def config_docker?
      config_value('docker', false)
    end

    def config_comments_since_disabled?
      config_value('comments_since_disabled', false)
    end

    def config_comments_since_disabled_set(value)
      @comments_since_most_recent_commit = nil
      config_value_set('comments_since_disabled', value)
    end

    def commit_not_thumbs?(commit)
      commit[:commit][:author][:name] != 'Thumbs'
    end

    def head_commits
      @head_commits ||= octokit_client.commits(pull_request.head.repo.full_name, pull_request.head.ref)
    end

    def base_commits
      @base_commits ||= octokit_client.commits(pull_request.base.repo.full_name, pull_request.base.ref)
    end

    def commit_timestamp(commit)
      to_timestamp(commit[:commit][:committer][:date])
    end

    def most_recent_commit
      return @most_recent_commit if @most_recent_commit
      head_commit = head_commits.detect {|c| commit_not_thumbs?(c) }
      base_commit = base_commits.detect {|c| commit_not_thumbs?(c) }

      head_commit_timestamp = commit_timestamp(head_commit)
      base_commit_timestamp = commit_timestamp(base_commit)
      @most_recent_commit =
          head_commit_timestamp > base_commit_timestamp ?
            head_commit : base_commit
    end

    def most_recent_commit_timestamp
      commit_timestamp(most_recent_commit)
    end

    def effective_approvals
      (approvals + comment_code_approvals).compact
    end

    def any_member_approvals
      reviews.select { |r| r['state'] == 'APPROVED' }.
        select { |a| to_timestamp(a['submittedAt']) > most_recent_commit_timestamp }.
        compact
    end

    def org_member_approvals
      approval_members = any_member_approvals.map { |a| a['author']['login'] }.uniq
      approval_members = approval_members.map {|u| [u, octokit_client.organization_member?(org, u)] }.to_h

      any_member_approvals.select { |approval|
        approval_members[approval["author"]["login"]]
      }.compact
    end

    def approvals
      if config_org_mode
        debug_message "returning org_member_code_approvals"
        return org_member_approvals
      end
      any_member_approvals
    end

    def approval_count
      approvals.map { |a| a["author"]["login"] }.uniq.length
    end

    def comment_code_approval_count
      comment_code_approvals.map { |r| r[:user][:login] }.uniq.length
    end

    def reviews_query(pr_id)
      GitHub::Client.parse <<-GRAPHQL
query {
  node(id: "#{pr_id}") {
    ... on PullRequest {
      id
      number
      reviews(last:10) {
        edges {
          node {
            author {
              id
              name
              login
            }
            body
            state
            submittedAt
          }
        }
      }
    }
  }
}
      GRAPHQL
    end

    def reviews
      return @reviews if @reviews
      query = reviews_query(pull_request.id)
      pr_hash = run_graph_query(query).data.to_h['node']
      if pr_hash && pr_hash.key?('reviews')
        @revies = pr_hash['reviews']['edges'].collect { |e| e['node'] }
      else
        @reviews = []
      end
    end

    def run_graph_query(query)
      debug_message "running graph query #{query}"
      result = GitHub::Client.query query
      debug_message "graph query result #{result}"
      result
    end

    def comment_code_approvals
      if config_org_mode
        debug_message "returning org_member_code_reviews"
        return org_member_code_reviews
      end
      code_reviews
    end

    def remove_build_dir
      FileUtils.mv(@build_dir, "#{@build_dir}.#{DateTime.now.strftime("%s")}")
    end

    def parse_thumbot_command(text_body)
      result_lines = text_body.split(/\n/).grep(/^thumbot/)
      return nil unless result_lines.length > 0
      command_string = result_lines.shift
      command_elements = command_string.split(/\s+/)
      return nil unless command_elements.length > 1
      command = command_elements[1].to_sym
      return nil unless command && [:retry, :merge].include?(command)
      command
    end

    def contains_thumbot_command?(text_body)
      command = parse_thumbot_command(text_body)
      command ? true : false
    end

    def run_thumbot_command(command)
      send("thumbot_#{command}") if [:retry, :merge].include?(command)
    end

    def thumbot_retry
      debug_message "received retry command"
      unpersist_build_status
      remove_build_dir
      clear_build_progress_comment
      set_build_progress(:in_progress)
      validate
      set_build_progress(:completed)
      create_build_status_comment
      debug_message "finished retry command"
      true
    end

    def thumbot_merge
      debug_message "received merge command"
      validate

      unless thumbs_config_present?
        add_comment "Sorry, can't merge without a .thumbs.yml in the branch"
        return false
      end
      config_auto_merge_set(true)
      return false unless valid_for_merge?
      create_reviewers_comment
      add_comment "Merging and closing this pr"
      merge
      true
    end

    def forked_repo_branch_pr?
      debug_message "pull_request.base.repo.full_name #{pull_request.base.repo.full_name}"
      debug_message "pull_request.head.repo.full_name #{pull_request.head.repo.full_name}"
      pull_request.base.repo.full_name != pull_request.head.repo.full_name
    end

    def inspect
      prefix = "#<#{self.class}:0x#{self.__id__.to_s(16)}"
      suffix = ">"
      "#{prefix} @repo=#{repo}, @pr=#{pr}, @build_dir=#{build_dir}#{suffix}"
    end

    def wait_lock?
      all_comments.any? {|comment| comment[:body] =~  /^thumbot wait/ }
    end

    private

    def render_template(template)
      ERB.new(template).result(binding)
    end

    def result_image(result)
      case result
        when :in_progress
          ":clock1:"
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

    def parse_github_pr_url(url)
      matches = github_pr_url_re.match(url)
      return if matches.nil?
      return "#{matches[4]}/#{matches[5]}", matches[6].to_i
    end

    def github_pr_url_re()
      /(http[s]?[:][\/]+)(([^\/]+.)?[^\/]+\.[^\/]+)\/([^\/]+)\/([^\/]+)\/pull\/([0-9]+)/
    end
  end
end
