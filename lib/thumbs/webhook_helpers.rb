require 'sinatra/base'

module Sinatra
  module WebhookHelpers
    def payload_type(payload)
      return :unregistered if payload.key?('comment') && ["thumbot"].include?(payload['comment']['user']['login'])
      return :new_pr if payload['action']=='opened' && payload.key?('pull_request') && payload['pull_request'].key?('number')
      return :new_comment if payload.key?('comment') && payload.key?('issue') && payload['comment'].key?('body')
      return :new_push if payload['action']=='synchronize'
      # return :new_base if payload['action']=='edited' &&
      #     payload.key?('changes') &&
      #     payload['changes'].key?('base') &&
      #     payload['changes']['base'].key?('ref') &&
      #     payload['changes']['base']['ref'].key?('from')
      # merged_base_keys=%w[ref before after commits head_commit pusher repository]
      # return :unregistered unless payload.key?('ref') && payload['ref'].length > 1
      # return :merged_base if (merged_base_keys.collect{|key| key if payload.key?(key) }.compact.length == merged_base_keys.length)
      :unregistered
    end

    def process_payload(payload)
      case payload_type(payload)
        # when :merged_base
        #   debug_message "merged_base payload"
        #   print payload.to_yaml
        #   print "payload"
        #   base=payload['ref'].split('/').pop
        #   [payload['repository']['full_name'], base]
        # when :new_base
        #   [payload['repository']['full_name'], payload['pull_request']['number']]
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
