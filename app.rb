$:.unshift(File.join(File.dirname(__FILE__), '/lib'))

require 'thumbs'
require 'sinatra/base'
require 'json'

class ThumbsWeb < Sinatra::Base
  helpers Sinatra::GeneralHelpers
  helpers Sinatra::WebhookHelpers
  enable :logging

  get '/' do
    "OK"
  end
  get '/status' do
    @octo_client = Octokit::Client.new(:netrc => true)
    release_dir=File.expand_path(File.dirname(__FILE__))
    version=release_dir.split(/\//).pop
    deployed_at=File.mtime(__FILE__)
    ENV.keys.each {|key| ENV.delete(key) if key =~ /(TOKEN|CLIENT_SECRET|PASS)/ }
    status= {
        status: "OK",
        version: version,
        release_dir: release_dir,
        deployed_at: deployed_at,
        github_user: @octo_client.login,
        authenticated: @octo_client.basic_authenticated?,
        rate_limit: @octo_client.ratelimit.to_h,
        env: ENV.to_hash.to_yaml,
        escript: ` which escript `
    }
    "<pre>#{status.to_yaml}</pre>"
  end
  get '/webhook' do
    "OK"
  end
  post '/webhook' do
    @octo_client = Octokit::Client.new(:netrc => true)
    payload = JSON.parse(request.body.read)
    print payload.to_yaml if ENV.key?('DEBUG')
    case payload_type(payload)
      when :new_pr
        repo, pr = process_payload(payload)
        debug_message "got repo #{repo} and pr #{pr}"
        sleep 1 # github sometimes needs time
        pr_worker = Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr)
        return "OK" unless pr_worker.open?
        return "OK" if pr_worker.build_in_progress?
        return "OK" unless pr_worker.thumb_config
        debug_message("new pull request #{pr_worker.repo}/pulls/#{pr_worker.pr.number} ")
        intro_text=<<-EOS
Thanks @#{pr_worker.pr.user.login}!
<details><Summary>Settings</Summary>

```yaml 
#{pr_worker.thumb_config.to_yaml} ```

</details>
        
        EOS
        pr_worker.add_comment(intro_text)
        pr_worker.set_build_progress(:in_progress)
        pr_worker.try_merge
        unless pr_worker.thumb_config && pr_worker.thumb_config.key?('build_steps')
          debug_message("no .thumbs config found for this repo/PR #{pr_worker.repo}##{pr_worker.pr.number}")
          return "OK"
        end

        pr_worker.validate
        pr_worker.set_build_progress(:completed)
        pr_worker.create_build_status_comment

        return "OK" unless pr_worker.review_count >= pr_worker.minimum_reviewers

        if pr_worker.valid_for_merge?
          pr_worker.create_reviewers_comment if pr_worker.review_count > 0
          pr_worker.add_comment "Merging and closing this pr"
          pr_worker.merge
        else
          debug_message("new pr #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end

      when :new_comment
        repo, pr = process_payload(payload)
        debug_message "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr)
        return "OK" unless pr_worker.open?
        debug_message("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} #{payload['comment']['body']}")
        debug_message payload['comment']['body']
        
        if pr_worker.contains_thumbot_command?(payload['comment']['body'])
          return "OK" unless pr_worker.thumb_config
          if pr_worker.thumb_config['org_mode']  && pr_worker.repo_is_org?
            commenting_user=payload['comment']['user']['login']
            unless pr_worker.org_member?(commenting_user)
              debug_message "thumb_config['org_mode']=true #{commenting_user} != org_member"
              return "ERROR"
            end
          end

          thumbot_command = pr_worker.parse_thumbot_command(payload['comment']['body'])
          result=pr_worker.run_thumbot_command( thumbot_command )
          status= result ? "OK" : "ERROR"
          return "COMMAND:#{thumbot_command}:#{status}"
        end

        debug_message ""
        unless pr_worker.build_progress_status == :completed
          debug_message "Build not yet completed, won't do anything else"
          return "OK"
        end
        
        debug_message "validate"
        pr_worker.validate

        if pr_worker.valid_for_merge?
          review_count=pr_worker.review_count
          unless review_count >= pr_worker.thumb_config['minimum_reviewers']
            debug_message " #{review_count} !>= #{pr_worker.thumb_config['minimum_reviewers']}"
            debug_message " reviewer rule not met "
            return false
          end

          debug_message("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
          pr_worker.create_reviewers_comment
          pr_worker.add_comment "Merging and closing this pr"
          pr_worker.merge
        else
          debug_message("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end
      when :code_approval
        repo, pr = process_payload(payload)
        debug_message "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr)
        return "OK" unless pr_worker.open?
        debug_message("new approval")
        pr_worker.validate

        if pr_worker.valid_for_merge?
          review_count=pr_worker.review_count
          unless review_count >= pr_worker.thumb_config['minimum_reviewers']
            debug_message " #{review_count} !>= #{pr_worker.thumb_config['minimum_reviewers']}"
            debug_message " reviewer rule not met "
            return false
          end

          debug_message("code approval #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
          pr_worker.create_reviewers_comment
          pr_worker.add_comment "Merging and closing this pr"
          pr_worker.merge
        else
          debug_message("code approval #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end
      when :new_push
        debug_message "This is a #{payload_type(payload).to_s}"
        repo, pr = process_payload(payload)
        debug_message "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr)
        return "OK" unless pr_worker.open?
        debug_message("new push on pull request #{pr_worker.repo}/pulls/#{pr_worker.pr.number} ")
        return "OK" if pr_worker.build_in_progress?
        pr_worker.set_build_progress(:in_progress)
        pr_worker.validate
        pr_worker.set_build_progress(:completed)
        pr_worker.create_build_status_comment


        if pr_worker.valid_for_merge?
          debug_message("new push #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
          pr_worker.merge
        else
          debug_message("new push #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end
      when :new_base
        debug_message "This is a #{payload_type(payload).to_s}"
        repo, pr = process_payload(payload)
        debug_message "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr)

        debug_message("#{payload_type(payload).to_s} on repo #{repo}")
        return "OK" if pr_worker.build_in_progress?
        pr_worker.set_build_progress(:in_progress)
        pr_worker.validate
        pr_worker.set_build_progress(:completed)
        pr_worker.create_build_status_comment


        if pr_worker.valid_for_merge?
          debug_message("new push #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
          pr_worker.merge
        else
          debug_message("new push #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end
      when :merged_base
        debug_message "This is a #{payload_type(payload).to_s}"
        repo, base_ref = process_payload(payload)
        debug_message "got repo #{repo} and base_ref #{base_ref}"
        pull_requests_for_base_branch = @octo_client.pull_requests(repo, :state => 'open').collect { |pr| pr if pr.base.ref == base_ref }.compact
        Process.detach(fork do
          pull_requests_for_base_branch.each do |pr|
            debug_message "Rebuild of PR: #{pr.number} with new Base ref #{base_ref}"
            pr_worker=Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr.number)
            next unless pr_worker.thumb_config
            ignore_after_n_days=90
            pr_created_at=DateTime.parse(pr_worker.pr.created_at.to_s).strftime("%s").to_i
            current_datetime=DateTime.now.strftime("%s").to_i
            horizon_datetime=current_datetime - ( ignore_after_n_days*86400 )

            if pr_created_at < horizon_datetime
                debug_message "PR: #{pr.number} is too old #{pr_worker.pr.created_at} to be considered. Ignored after #{ignore_after_n_days}+ days."
                next
            end

            if pr_worker.build_in_progress?
                debug_message "PR: #{pr.number} build_in_progress : next"
                next
            end

            pr_worker.set_build_progress(:in_progress)
            pr_worker.validate
            pr_worker.set_build_progress(:completed)
            pr_worker.create_build_status_comment

            if pr_worker.valid_for_merge?
              debug_message("merged base #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
              pr_worker.merge
            else
              debug_message("merged base #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
            end

          end
        end)
      when :unregistered
        debug_message "#{payload.to_yaml}"
        debug_message "This is not an event I recognize,: ignoring"
        debug_message payload_type(payload)
    end
    "OK"
  end
end

