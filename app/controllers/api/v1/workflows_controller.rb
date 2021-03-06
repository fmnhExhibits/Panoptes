require 'model_version'

class Api::V1::WorkflowsController < Api::ApiController
  include Versioned
  include TranslatableResource

  require_authentication :update, :create, :destroy, :retire_subjects, scopes: [:project]

  resource_actions :index, :show, :create, :update, :deactivate
  schema_type :json_schema

  def index
    unless params.has_key?(:sort)
      @controlled_resources = controlled_resources.rank(:display_order)
    end
    experiment_name = :eager_load_workflows
    sms_ids = CodeExperiment.run "#{experiment_name}" do |e|
      e.run_if { Panoptes.flipper[experiment_name].enabled? }
      e.context user: api_user
      e.use { }
      e.try do
        @controlled_resources = @controlled_resources
          .eager_load(:subject_sets, :expert_subject_sets, :attached_images)
      end
      #skip the mismatch reporting...we just want perf metrics
      e.ignore { true }
      super
    end
  end

  def update_links
    super { |workflow| post_link_actions(workflow) }
  end

  def destroy_links
    super { |workflow| post_link_actions(workflow) }
  end

  def retire_subjects
    operation.with(workflow: controlled_resource).run!(params)
    render nothing: true, status: 204
  end

  private

  def context
    case action_name
    when "show", "index"
      { languages: current_languages }.merge field_context
    else
      {}
    end
  end

  def field_context
    if params[:fields].present?
      included_keys = params[:fields].split(',')
      attrs = WorkflowSerializer.serializable_attributes.with_indifferent_access
      allowed_keys = attrs.slice(*included_keys).keys | ['id']
      excluded_fields = attrs.keys - allowed_keys
      { }.tap do |attributes|
        excluded_fields.each do |field|
          attributes[:"include_#{ field }?"] = false
        end
      end
    else
      { }
    end
  end

  # This is a very good reason to move away from the api controller work we've got
  # it's hard to hook into the right place to run actions that in theory should
  # be easily located in specific controller actions
  def post_link_actions(workflow)
    if workflow.set_member_subjects.exists?
      using_cellect = Panoptes.use_cellect?(workflow)

      case relation
      when :retired_subjects, 'retired_subjects'
        WorkflowRetiredCountWorker.perform_async(workflow.id)
        if using_cellect
          params[:retired_subjects].each do |subject_id|
            RetireCellectWorker.perform_async(subject_id, workflow.id)
          end
        end
      when :subject_sets, 'subject_sets'
        UnfinishWorkflowWorker.perform_async(workflow.id)
        ReloadCellectWorker.perform_async(workflow.id) if using_cellect
      end

    end
  end

  def build_update_hash(update_params, id)
    workflow = Workflow.find(id)
    WorkflowContent.transaction(requires_new: true) do
      if update_params.has_key? :tasks
        stripped_tasks, strings = extract_strings(update_params[:tasks])
        update_params[:tasks] = stripped_tasks
        workflow.primary_content.update(strings: strings)
      end
      reject_live_project_changes(workflow, update_params)
    end
    super(update_params, id)
  end

  def build_resource_for_create(create_params)
    stripped_tasks, strings = extract_strings(create_params[:tasks])
    create_params[:tasks] = stripped_tasks
    create_params[:active] = false if project_live?
    workflow = super(create_params)
    workflow.workflow_contents.build(
      strings: strings,
      language: workflow.primary_language
    )
    workflow
  end

  def extract_strings(tasks)
    task_string_extractor = TasksVisitors::ExtractStrings.new
    task_string_extractor.visit(tasks)
    [tasks, task_string_extractor.collector]
  end

  def add_relation(resource, relation, value)
    if relation == :retired_subjects && value.is_a?(Array)
      resource.save!
      value.each {|id| resource.retire_subject(id) }
      resource.reload
    else
      super
    end
  end

  def new_items(resource, relation, value)
    case relation
    when :retired_subjects, 'retired_subjects'
      resource.save!
      value.flat_map {|id| resource.retire_subject(id) }
      resource.reload
    when :subject_sets, 'subject_sets'
      items = construct_new_items(super(resource, relation, value), resource.project_id)
      if items.any? { |item| item.is_a?(SubjectSet) }
        items
      else
        items.first
      end
    else
      super
    end
  end

  def construct_new_items(item_scope, workflow_project_id)
    Array.wrap(item_scope).map do |item|
      if item.is_a?(SubjectSet) && !item.belongs_to_project?(workflow_project_id)
        SubjectSetCopier.new(item, workflow_project_id).duplicate_subject_set_and_subjects
      else
        item
      end
    end
  end

  def reject_live_project_changes(workflow, update_hash)
    if workflow.active && workflow.project.live && non_permitted_changes?(workflow, update_hash)
      raise Api::LiveProjectChanges.new("Can't change an active workflow for a live project.")
    end
  end

  def non_permitted_changes?(workflow, hash)
    %i(tasks grouped prioritized pairwise first_task).any? do |field|
      if hash.has_key? field
        !(workflow.send(field) == hash[field])
      else
        false
      end
    end
  end

  def project_live?
    project_from_params.try(:live)
  end

  def project_from_params
    project_id = params_for[:links].try(:[], :project)
    if project_id && project = Project.find_by(id: project_id)
      project
    end
  end

  def assoc_class(relation)
    case relation
    when :retired_subjects, "retired_subjects"
      SubjectWorkflowStatus
    else
      super
    end
  end
end
