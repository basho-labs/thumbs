require 'sinatra/base'

module Sinatra
  module WebhookHelpers
    def payload_type(payload)
      return :unregistered if payload.key?('comment') && ["thumbot"].include?(payload['comment']['user']['login'])
      return :new_pr       if payload['action']=='opened' && payload.key?('pull_request') && payload['pull_request'].key?('number')
      return :new_comment  if payload['action']=='created' && payload.key?('comment') && payload.key?('issue') && payload['comment'].key?('body')
      return :new_push     if payload['action']=='synchronize'
      return :new_base     if payload['action']=='edited' &&
          payload.key?('changes') &&
          payload['changes'].key?('base') &&
          payload['changes']['base'].key?('ref') &&
          payload['changes']['base']['ref'].key?('from')
      merged_base_keys=%w[ref before after commits head_commit pusher repository]

      if payload.key?('ref') && payload['ref'].length > 1
        matched_keys=merged_base_keys.collect{|key| key if payload.key?(key) }.compact
        return :merged_base if (matched_keys.length == merged_base_keys.length)
      end
      return :code_approval if payload['action'] == 'submitted' &&
          payload.key?('review') &&
          payload['review'].key?('state') &&
          payload['review']['state'] == 'approved'
      return :code_comment if payload['action'] == 'submitted' &&
          payload.key?('review') &&
          payload['review'].key?('state') &&
          payload['review']['state'] == 'commented'
      return :code_change_requested if payload['action'] == 'submitted' &&
          payload.key?('review') &&
          payload['review'].key?('state') &&
          payload['review']['state'] == 'changes_requested'
      :unregistered
    end

    def process_payload(payload)
      case payload_type(payload)
        when :code_change_requested
          debug_message "code change payload"
          [payload['repository']['full_name'], payload['pull_request']['number']]
        when :code_comment
          debug_message "code comment payload"
          [payload['repository']['full_name'], payload['pull_request']['number']]
        when :code_approval
          debug_message "code approval payload"
          [payload['repository']['full_name'], payload['pull_request']['number']]
        when :merged_base
          debug_message "merged_base payload"
          base=payload['ref'].split('/').pop
          [payload['repository']['full_name'], base]
        when :new_base
          [payload['repository']['full_name'], payload['pull_request']['number']]
        when :new_push
          [payload['repository']['full_name'], payload['pull_request']['number']]
        when :new_pr
          [payload['repository']['full_name'], payload['pull_request']['number']]
        when :new_comment
          [payload['repository']['full_name'], payload['issue']['number']]
        when :unregistered
          nil
      end
    end
  end
end
