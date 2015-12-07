class CalculateProjectCompletenessWorker
  include Sidekiq::Worker
  using Refinements::RangeClamping

  def perform(project_id)
    Project.transaction do
      project = Project.find(project_id)
      project.workflows.all.each do |workflow|
        workflow.update! completeness: workflow_completeness(workflow)
      end

      project.update! completeness: project_completeness(project)
    end
  end

  def project_completeness(project)
    completenesses = project.workflows.map(&:completeness)
    completenesses.sum / completenesses.size.to_f
  end

  def workflow_completeness(workflow)
    return 0.0 if workflow.subjects.count == 0

    case workflow.retirement_scheme
    when RetirementSchemes::ClassificationCount
      total_subjects = workflow.subjects.count
      retired_subjects = workflow.retired_subjects_count
      classifications_needed = total_subjects * workflow.retirement_scheme.count
      classifications_made = workflow.classifications_count
      max = (retired_subjects >= total_subjects) ? 1.0 : 0.9

      (0.0..max).clamp(classifications_made / classifications_needed.to_f)
    else
      0.0
    end
  end
end