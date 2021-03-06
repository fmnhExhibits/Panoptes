require 'subjects/strategy_selection'

class EnqueueSubjectQueueWorker
  include Sidekiq::Worker

  sidekiq_options queue: :really_high

  sidekiq_options congestion: Panoptes::SubjectEnqueue.congestion_opts.merge({
    key: ->(queue_id) {
      "queue_#{ queue_id }_enqueue"
    }
  })

  def perform(queue_id, sms_ids)
    queue = SubjectQueue.find(queue_id)
    queue.enqueue_update(sms_ids) unless sms_ids.empty?
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
