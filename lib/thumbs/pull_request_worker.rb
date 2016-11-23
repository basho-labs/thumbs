module Thumbs
  class PullRequestWorker
    attr_reader :build_dir
    attr_reader :build_status
    attr_accessor :build_steps
    attr_reader :minimum_reviewers
    attr_reader :repo
    attr_reader :pr
    attr_accessor :thumb_config
    attr_reader :log
    attr_reader :org
    attr_accessor :client
    attr_reader :pull_request_id

    def initialize(options)
      @repo = options[:repo]
      @org = repo.split('/').first
      @client = Octokit::Client.new(:netrc => true)
      @pr = @client.pull_request(options[:repo], options[:pr])
      @pull_request_id=get_pull_request_id
      @build_dir=options[:build_dir] || "/tmp/thumbs/#{build_guid}"
      @build_status={:steps => {}}
      @build_steps = []
      prepare_build_dir
      load_thumbs_config
      @minimum_reviewers = thumb_config && thumb_config.key?('minimum_reviewers') ? thumb_config['minimum_reviewers'] : 2
      @timeout=thumb_config && thumb_config.key?('timeout') ? thumb_config['timeout'] : 1800
    end

    def reset_build_status
      @build_status={:steps => {}}
    end

    def prepare_build_dir
      cleanup_build_dir
      clone
      try_merge
    end

    def cleanup_build_dir
      FileUtils.rm_rf(@build_dir)
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
        return status
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
        git.checkout(most_recent_head_sha)
        git.checkout(@pr.base.ref)
        git.branch(pr_branch).checkout
        debug_message "Trying merge #{@repo}:PR##{@pr.number} \" #{@pr.title}\" #{most_recent_head_sha} onto #{@pr.base.ref} #{most_recent_base_sha}"
        merge_result = git.merge("#{most_recent_head_sha}")
        load_thumbs_config
        status[:ended_at]=DateTime.now
        status[:result]=:ok
        status[:message]="Merge Success: #{@pr.head.ref} #{most_recent_head_sha} onto target branch: #{@pr.base.ref} #{most_recent_base_sha}"
        status[:output]=merge_result
      rescue => e
        debug_message "Merge Failed: #{@pr.head.ref} #{most_recent_head_sha} onto target branch: #{@pr.base.ref} #{most_recent_base_sha}"
        debug_message "PR ##{@pr[:number]} END"

        status[:result]=:error
        status[:message]="Merge Failed: #{@pr.head.ref} #{most_recent_head_sha} onto target branch: #{@pr.base.ref} #{most_recent_base_sha}"
        status[:output]=e.inspect
      end

      @build_status[:steps][:merge]=status
      status
    end

    def run_command_in_docker(command)
      image=thumb_config['docker_image']||'ubuntu'
      shell=thumb_config['shell']||'/bin/bash'
      command = "source /etc/bash.bashrc; #{command}"
      docker_command="sudo docker run -t"
      (thumb_config['env']||{}).each do |variable_key,variable_value|
        docker_command << " -e #{variable_key}=#{variable_value}"
      end
      docker_command << " -v ~/.bashrc:/etc/bash.bashrc -v /tmp/thumbs:/tmp/thumbs"
      docker_command << " #{image} #{shell} -c '#{command}'"

      debug_message docker_command
      output, exit_code = run_command_in_shell(docker_command)
      [output, exit_code]
    end

    def run_command_in_shell(command)
      shell=thumb_config['shell']||'/bin/bash'

      output, exit_code = nil

      Open3.popen2e(ENV, shell) do|stdin, stdout_and_stderr, wait_thr|
          stdin.puts "source ~/.bashrc"
          stdin.puts "#{command} 2>&1"
          stdin.close
          pid = wait_thr.pid
          output=stdout_and_stderr.read
          exit_code = wait_thr.value.exitstatus
      end
      [output, exit_code]
    end

    def run_command(command)
      if thumb_config['docker']
        run_command_in_docker(command)
      else
        run_command_in_shell(command)
      end
    end

    def try_run_build_step(name, command)
      status={}

      command = "cd #{@build_dir}; #{command}"

      debug_message "running command #{command}"

      status[:started_at]=DateTime.now
      status[:command] = command
      status[:env]=(thumb_config.key?('env') ? thumb_config['env'] : {})

      status[:env].each do |key, value|
        ENV[key]="#{value}"
      end
      begin
        Timeout::timeout(thumb_config['timeout']) do
          output, exit_code = run_command(command)
          unless output && output.strip != ""
            output = "No output"
          end
          status[:ended_at]=DateTime.now
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

    def events
      client.repository_events(@repo).collect { |e| e.to_h }
    end

    def push_time_stamp(sha)
      time_stamp=events.collect { |e| e[:created_at] if e[:type] == 'PushEvent' && e[:payload][:head] == sha }.compact.first
      time_stamp ? time_stamp : pr.created_at
    end

    def comments_after_most_recent_commit
      comments_after_sha=all_comments.compact.collect do |c|
        comment_timestamp=DateTime.parse(c[:created_at].to_s)
        c.to_h if comment_timestamp > most_recent_commit_timestamp
      end.compact
    end

    def all_comments
      client.issue_comments(repo, pr.number, per_page: 100)
    end

    def comments
      comments_after_most_recent_commit
    end

    def bot_comments
      comments.collect { |c| c if ["thumbot"].include?(c[:user][:login]) }.compact
    end

    def contains_plus_one?(comment_body)
      (/:\+1:/.match(comment_body) || /\+1/.match(comment_body) || /\\U0001F44D/.match(comment_body.to_yaml)) ? true : false
    end

    def non_author_comments
      comments.collect { |comment| comment if @pr[:user][:login] != comment[:user][:login] && !["thumbot"].include?(comment[:user][:login]) }.compact
    end

    def org_member_comments
      org = @repo.split(/\//).shift
      non_author_comments.collect { |comment| comment if @client.organization_member?(org, comment[:user][:login]) }.compact
    end

    def org_member_code_reviews
      org_member_comments.collect { |comment| comment if contains_plus_one?(comment[:body]) }.compact
    end

    def code_reviews
      non_author_comments.collect { |comment| comment if contains_plus_one?(comment[:body]) }.compact
    end

    def review_count
      approval_logins=approvals.collect { |a| a["author"]["login"] }.uniq
      comment_code_approval_logins=comment_code_approvals.collect { |r| r[:user][:login] }.uniq
      countable_reviews = (approval_logins + comment_code_approval_logins).uniq
      countable_reviews.length
    end

    def reviews
      (approvals + comment_code_approvals).compact
    end

    def debug_message(message)
      log = Log4r::Logger['Thumbs']
      if log
        log.debug("#{@repo} #{@pr.number} #{@pr.state} #{message}")
      end
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

      unless @build_status.key?(:steps)
        debug_message "contains no steps"
        return false
      end
      unless @build_status[:steps].key?(:merge)
        debug_message "contains no merge step"

        return false
      end

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

      unless thumb_config
        debug_message "config missing"
        return false
      end
      unless thumb_config.key?('minimum_reviewers')
        debug_message "minimum_reviewers config option missing"
        return false
      end
      review_count_value=review_count
      debug_message "minimum reviewers: #{thumb_config['minimum_reviewers']}"
      debug_message "review_count: #{review_count_value} >= #{thumb_config['minimum_reviewers']}"

      unless review_count_value >= thumb_config['minimum_reviewers']
        debug_message " #{review_count_value} !>= #{thumb_config['minimum_reviewers']}"
        return false
      end

      unless thumb_config['merge'] == true
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
      "#{pr.base.ref.gsub(/\//, '_')}.#{most_recent_base_sha.slice(0, 7)}.#{pr.head.ref.gsub(/\//, '_')}.#{most_recent_head_sha.slice(0, 7)}"
    end

    def set_build_progress(progress_status)
      update_or_create_build_status(most_recent_head_sha, progress_status)
    end

    def compose_build_status_comment_title(progress_status)
      pr = client.pull_request(repo, @pr.number)
      status_emoji=(progress_status==:completed ? result_image(aggregate_build_status_result) : result_image(progress_status))
      comment_title="|||||\n"
      comment_title<<"------------ | -------------|------------ | ------------- \n"
      comment_title<<"#{pr.head.ref} #{most_recent_head_sha.slice(0, 7)} | :arrow_right: | #{pr.base.ref} #{most_recent_base_sha.slice(0, 7)} | #{status_emoji} #{progress_status}"
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
      bot_comments.collect do |c|
        next unless c[:body].lines.length > 1
        status_line = c[:body].lines[2]
        pr = client.pull_request(repo, @pr.number)
        next unless status_line =~ /^#{pr.head.ref} #{most_recent_head_sha.slice(0, 7)} \| :arrow_right: \| #{pr.base.ref} #{most_recent_base_sha.slice(0, 7)}/
        c
      end.compact[0] || {:body => ""}
    end

    def comments_after_sha(sha)
      sha_time_stamp=push_time_stamp(sha)
      comments_after_sha=all_comments.compact.collect do |c|
        c.to_h if c[:created_at] > sha_time_stamp
      end.compact
    end

    def update_or_create_build_status(sha, progress_status)
      if build_progress_status == :unstarted
        set_build_status_comment(sha, progress_status)
      else
        comment=get_build_progress_comment
        comment_id = comment[:id]
        debug_message "comment id is #{comment_id}"
        comment_message=compose_build_status_comment_title(progress_status)
        debug_message comment_message
        update_pull_request_comment(comment_id, comment_message)
      end
    end

    def update_pull_request_comment(comment_id, comment_message)
      begin
        comment = client.issue_comment(repo, comment_id)
        unless comment && comment.key?(:id)
          debug_message "comment doesnt exist"
          return nil
        end
      rescue Octokit::NotFound => e
        debug_message "comment doesnt exist"
        return nil
      end
      client.update_comment(repo, comment[:id], comment_message)
    end

    def sanitize_text(text)
      text.to_s.encode('UTF-8', 'UTF-8', :invalid => :replace, :undef => :replace)
    end
    def create_gist_from_status(name, content)
      file_title="#{name.to_s.gsub(/\//,'_')}.txt"
      client.create_gist( { :files => { file_title => { :content => content || "no output" } } } )
    end
    def clear_build_progress_comment
      build_progress_comment = get_build_progress_comment
      build_progress_comment ? client.delete_comment(repo, build_progress_comment[:id]) : true
    end

    def pushes
      events.collect { |e| e if e[:type] == 'PushEvent' }.compact
    end

    def most_recent_sha
      most_recent_head_sha
    end

    def run_build_steps
      debug_message "begin run_build_steps"
      build_steps.each do |build_step|
        build_step_name=build_step.gsub(/\s+/, '_').gsub(/-/, '')
        debug_message "run build step #{build_step_name} begin"
        try_run_build_step(build_step_name, build_step)
        debug_message "run build step #{build_step_name} end"
        persist_build_status
        debug_message "run build step #{build_step_name} persist"
      end
    end

    def persist_build_status
      repo=@repo.gsub(/\//, '_')
      file=File.join('/tmp/thumbs', "#{repo}_#{build_guid}.yml")
      FileUtils.mkdir_p('/tmp/thumbs')
      build_status[:steps].keys.each do |build_step|
        next unless build_status[:steps][build_step].key?(:output)
        output = build_status[:steps][build_step][:output]
        build_status[:steps][build_step][:output] = sanitize_text(output)
      end
      File.open(file, "w") do |f|
        f.syswrite(build_status.to_yaml)
      end
      true
    end

    def unpersist_build_status
      repo=@repo.gsub(/\//, '_')
      file=File.join('/tmp/thumbs', "#{repo}_#{build_guid}.yml")
      File.delete(file) if File.exist?(file)
    end

    def read_build_status
      repo=@repo.gsub(/\//, '_')
      file=File.join('/tmp/thumbs', "#{repo}_#{build_guid}.yml")
      if File.exist?(file)
        YAML.load(IO.read(file))
      else
        {:steps => {}}
      end
    end

    def validate
      build_status = read_build_status

      unless build_status.key?(:steps) && build_status[:steps].keys.length > 0
        debug_message "no build status found, running build steps"
        refresh_repo
        try_merge
        run_build_steps
      else
        debug_message "using persisted build status"
      end
      true

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
        merge_comment="Successfully merged *#{@repo}/pulls/#{@pr.number}* (*#{most_recent_head_sha}* on to *#{@pr.base.ref}*)\n\n"
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

    def add_comment(comment, options={})
      client.add_comment(@repo, @pr.number, comment, options = {})
    end

    def close
      client.close_pull_request(@repo, @pr.number)
    end

    def open_pull_requests
      client.pull_requests(@repo, :state => 'open')
    end

    def commits
      client.commits(repo, pr.head.ref)
    end

    def most_recent_head_sha
      client.commits(repo, pr.head.ref).first[:sha]
    end

    def most_recent_base_sha
      client.commits(repo, pr.base.ref).first[:sha]
    end

    def pull_requests_for_base_branch(branch)
      open_pull_requests.collect { |pr| pr if pr.base.ref == branch }
    end

    def build_status_problem_steps
      @build_status[:steps].collect { |step_name, status| step_name if status[:result] != :ok }.compact
    end

    def aggregate_build_status_result
      build_status[:steps].each do |step_name, status|
        return :error unless status.kind_of?(Hash) && status.key?(:result) && status[:result] == :ok
      end
      :ok
    end

    def create_build_status_comment
      if aggregate_build_status_result == :ok
        @status_title="\n<details><Summary>Looks good!  :+1: </Summary>"
      else
        @status_title="\n<details><Summary>There seems to be an issue with build step **#{build_status_problem_steps.join(",")}** !  :cloud: </Summary>"
      end

      build_comment = render_template <<-EOS
<% @build_status[:steps].each do |step_name, status| %>
<% if status[:output] %>
<% gist=create_gist_from_status(step_name, status[:output]) %>
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

<%= status[:output] %>

```

--------------------------------------------------

</details>

<% end %>
<%= render_reviewers_comment_template %>

</details>
      EOS
      comment_id = get_build_progress_comment[:id]
      comment_message = compose_build_status_comment_title(:completed)
      comment_message << "\n#{@status_title}"
      comment_message << build_comment
      update_pull_request_comment(comment_id, comment_message)
    end

    def render_reviewers_comment_template
      comment = render_template <<-EOS
<% status_code= (review_count >= minimum_reviewers ? :ok : :unchecked) %>
<% org_msg=  thumb_config['org_mode'] ? " from organization #{repo.split(/\//).shift}"  : "." %>
<details>
<summary><%= result_image(status_code) %> <%= review_count %> of <%= minimum_reviewers %> Code reviews<%= org_msg %></summary>
<% reviews.each do |review| %>
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

    def get_open_pull_requests_for_repo
      org, repo_name = @repo.split('/')
      GitHub::Client.parse <<-GRAPHQL
        query {
          repositoryOwner(login: "#{org}"){
            repository(name: "#{repo_name}") {
              pullRequests(states:OPEN, last: 2) {
                edges {
                  node{
                    id
                    number
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    def get_pull_request_id
      prs_for_repo_query=get_open_pull_requests_for_repo
      pr_list=run_graph_query(prs_for_repo_query).data.to_h
      unless pr_list.key?('repositoryOwner') && pr_list['repositoryOwner'].key?('repository')
        debug_message("pr_list does not contain repositoryOwner and repository key: #{pr_list}")
        return nil
      end

      graph_repo=pr_list['repositoryOwner']['repository']
      my_pull_request_id=graph_repo['pullRequests']['edges'].collect do |n|
        next unless n.key?('node')
        next unless n['node'].key?('id')
        next unless n['node']['number'].to_i == @pr.number.to_i
        n['node']['id']
      end.compact.first
      debug_message "my pull request id: #{my_pull_request_id}"
      my_pull_request_id
    end

    def get_pull_request_by_id(id)
      GitHub::Client.parse <<-GRAPHQL
   query {
    node(id: "#{id}") {
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

    def most_recent_commit_timestamp
      head_commits=client.commits(repo, pr.head.ref)
      base_commits=client.commits(repo, pr.base.ref)
      head_commit_timestamp = DateTime.parse(head_commits.first[:commit][:committer][:date].to_s)
      base_commit_timestamp = DateTime.parse(base_commits.first[:commit][:committer][:date].to_s)
      head_commit_timestamp > base_commit_timestamp ? head_commit_timestamp : base_commit_timestamp
    end

    def get_approvals(id)
      approval_entries=get_reviews_by_pr_id(id).collect { |r| r if r['state'] == 'APPROVED' }.compact
      approval_entries=approval_entries.collect do |a|
        approval_timestamp_int=DateTime.parse(a['submittedAt'])
        a if approval_timestamp_int > most_recent_commit_timestamp
      end
      approval_entries.compact
    end

    def org_member_approvals
      get_approvals(pull_request_id).collect { |approval| approval if @client.organization_member?(org, approval["author"]["login"]) }.compact
    end

    def approvals
      if @thumb_config.key?('org_mode') && @thumb_config['org_mode']
        debug_message "returning org_member_code_approvals"
        return org_member_approvals
      end
      get_approvals(pull_request_id)
    end

    def approval_count
      approvals.collect { |a| a["author"]["login"] }.uniq.length
    end

    def comment_code_approval_count
      comment_code_approvals.collect { |r| r[:user][:login] }.uniq.length
    end

    def get_reviews_by_pr_id(id)
      pr_hash = run_graph_query(get_pull_request_by_id(id)).data.to_h['node']
      pr_hash ? (pr_hash.key?('reviews') ? pr_hash['reviews']['edges'].collect { |e| e['node'] } : []) : []
    end

    def run_graph_query(query)
      debug_message "running graph query #{query}"
      result=GitHub::Client.query query
      debug_message "graph query result #{result}"
      result
    end

    def comment_code_approvals
      if @thumb_config['org_mode']
        debug_message "returning org_member_code_reviews"
        return org_member_code_reviews
      end

      code_reviews
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
  end
end
