module Bosh::Director
  module Api
    class ResurrectorManager
      def set_pause_for_instance(deployment_name, job_name, index_or_id, desired_state)

        # This is for backwards compatibility and can be removed when we move to referencing job by instance id only.
        if index_or_id.to_s =~ /^\d+$/
          instance = InstanceLookup.new.by_attributes(deployment_name, job_name, index_or_id)
        else
          instance = InstanceLookup.new.by_uuid(deployment_name, job_name, index_or_id)
        end

        instance.resurrection_paused = desired_state
        instance.save
      end

      def set_pause_for_all(desired_state)
        Models::Instance.update(resurrection_paused: desired_state)
      end
    end
  end
end