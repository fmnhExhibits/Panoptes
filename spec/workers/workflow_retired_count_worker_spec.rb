require "spec_helper"

RSpec.describe WorkflowRetiredCountWorker do
  subject(:worker) { WorkflowRetiredCountWorker.new }
  let(:workflow) { create(:workflow) }

  describe "#perform" do

    it 'should update the workflow retired count' do
      allow(Workflow).to receive(:find).and_return(workflow)
      expect(workflow)
        .to receive(:update_column)
        .with(:retired_set_member_subjects_count, anything)
      worker.perform(workflow.id)
    end

    it 'should use a workflow counter to do it' do
      counter = instance_double(WorkflowCounter, retired_subjects: 0)
      expect(WorkflowCounter).to receive(:new).with(workflow).and_return(counter)
      worker.perform(workflow.id)
    end
  end

  describe "finishing workflows" do
    before do
      allow_any_instance_of(SubjectWorkflowStatus)
        .to receive(:retire?)
        .and_return(true)
    end

    it 'should not mark the workflow as finished when it is not' do
      allow(workflow).to receive(:finished?).and_return(false)
      expect do
        worker.perform(workflow.id)
      end.to_not change{ Workflow.find(workflow.id).finished_at }
    end

    context "workflow is finished" do
      before do
        allow_any_instance_of(Workflow)
          .to receive(:finished?)
          .and_return(true)
      end

      it 'should set workflow.finished_at to the current time' do
        expect do
          worker.perform(workflow.id)
        end.to change{ Workflow.find(workflow.id).finished_at }.from(nil)
      end

      context "when the workflow optimistic lock is updated" do
        it 'should save the changes and not raise an error' do
          Workflow.find(workflow.id).touch
          expect { worker.perform(workflow.id) }.to_not raise_error
        end
      end
    end
  end
end
