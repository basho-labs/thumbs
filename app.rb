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
    case payload_type(payload)
      when :new_pr
        repo, pr = process_payload(payload)
        debug_message "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr)
        return "OK" unless pr_worker.open?
        debug_message("new pull request #{pr_worker.repo}/pulls/#{pr_worker.pr.number} ")
        pr_worker.add_comment("Thanks @#{pr_worker.pr.user.login}!")
        pr_worker.validate
        pr_worker.add_comment " .thumbs.yml config:\n``` #{pr_worker.thumb_config.to_yaml} ```"

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

        pr_worker.validate
        pr_worker.load_thumbs_config
        if pr_worker.valid_for_merge?

          unless pr_worker.review_count >= pr_worker.thumb_config['minimum_reviewers']
            debug_message " #{pr_worker.review_count} !>= #{pr_worker.thumb_config['minimum_reviewers']}"
           return false
          end


          debug_message("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
          pr_worker.create_reviewers_comment
          pr_worker.add_comment "Merging and closing this pr"
          pr_worker.merge
        else
          debug_message("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end
      when :new_push
        debug_message "This is a new push"
        repo, pr = process_payload(payload)
        debug_message "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo => repo, :pr => pr)
        return "OK" unless pr_worker.open?
        debug_message("new push on pull request #{pr_worker.repo}/pulls/#{pr_worker.pr.number} ")
        pr_worker.validate
        pr_worker.create_build_status_comment

        if pr_worker.valid_for_merge?
          debug_message("new push #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
          pr_worker.merge
        else
          debug_message("new push #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end
      when :unregistered
        debug_message "This is not an event I recognize,: ignoring"
        debug_message payload_type(payload)
    end
    "OK"
  end
end

