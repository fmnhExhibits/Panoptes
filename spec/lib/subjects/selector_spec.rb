require 'spec_helper'

RSpec.describe Subjects::Selector do
  let(:workflow) { create(:workflow_with_subject_set) }
  let(:subject_set) { workflow.subject_sets.first }
  let(:user) { create(:user) }
  let!(:smses) { create_list(:set_member_subject, 10, subject_set: subject_set).reverse }
  let(:params) { {} }

  subject { described_class.new(user, workflow, params, Subject.all) }

  describe "#get_subjects" do
    it 'should return url_format: :get in the context object' do
      _, ctx = subject.get_subjects
      expect(ctx).to include(url_format: :get)
    end

    context "when the workflow doesn't have any subject sets" do
      it 'should raise an informative error' do
        allow_any_instance_of(Workflow).to receive(:subject_sets).and_return([])
        expect{subject.get_subjects}.to raise_error(
          Subjects::Selector::MissingSubjectSet,
          "no subject set is associated with this workflow"
        )
      end
    end

    context "when the subject sets have no data" do
      it 'should raise the an error' do
        allow_any_instance_of(Workflow)
          .to receive(:set_member_subjects).and_return([])
        message = "No data available for selection"
        expect {
          subject.get_subjects
        }.to raise_error(Subjects::Selector::MissingSubjects, message)
      end
    end

    context "normal selection" do
      it 'should request strategy selection', :aggregate_failures do
        selector = instance_double("Subjects::StrategySelection")
        expect(selector).to receive(:select).and_return([1])
        expect(Subjects::StrategySelection).to receive(:new).and_return(selector)
        subject.get_subjects
      end

      it 'should return the default subjects set size' do
        subjects, = subject.get_subjects
        expect(subjects.length).to eq(10)
      end

      context "when the params page size is set as a string" do
        let(:size) { 2 }
        subject do
          params = { page_size: size }
          described_class.new(user, workflow, params, Subject.all)
        end

        it 'should return the page_size number of subjects' do
          subjects, _context = subject.get_subjects
          expect(subjects.length).to eq(size)
        end
      end
    end

    context "when the database selection strategy returns an empty set" do
      before do
        allow_any_instance_of(Subjects::PostgresqlSelection)
        .to receive(:select).and_return([])
        expect_any_instance_of(Subjects::PostgresqlSelection)
          .to receive(:any_workflow_data)
          .and_call_original
      end

      it 'should fallback to selecting some data' do
        subjects, _context = subject.get_subjects
      end

      context "and the workflow is grouped" do
        let(:subject_set_id) { subject_set.id }
        let(:params) { { subject_set_id: subject_set_id } }

        it 'should fallback to selecting some grouped data' do
          allow_any_instance_of(Workflow).to receive(:grouped).and_return(true)
          subjects, _context = subject.get_subjects
        end
      end
    end
  end

  describe '#selected_subjects' do

    context "with retired subjects" do
      let(:retired_workflow) { workflow }
      let(:sms) { smses[0] }
      let!(:sws) do
        create(:subject_workflow_status,
          subject: sms.subject,
          workflow: retired_workflow,
          retired_at: Time.zone.now
        )
      end
      let(:result) { subject.selected_subjects.map(&:id) }

      it 'should not return retired subjects' do
        expect(result).not_to include(sws.id)
      end

      context "when the sms is retired for a different workflow" do
        let(:retired_workflow) { create(:workflow, project: workflow.project) }

        it 'should return all the subjects' do
          expect(result).to match_array(smses.map(&:subject_id))
        end
      end
    end

    it 'should not return deactivated subjects' do
      deactivated_ids = smses[0..smses.length-2].map(&:subject_id)
      Subject.where(id: deactivated_ids).update_all(activated_state: 1)
      result_ids = subject.selected_subjects.pluck(&:id)
      expect(result_ids).not_to include(*deactivated_ids)
    end

    it 'should return something when everything selected is retired' do
      smses.each do |sms|
        swc = create(:subject_workflow_status, subject: sms.subject, workflow: workflow, retired_at: Time.zone.now)
      end
      expect(subject.selected_subjects.size).to be > 0
    end

    it "should respect the order of the sms selection" do
      ordered_sms = smses.sample(5)
      sms_ids = ordered_sms.map(&:id)
      expect(subject).to receive(:run_strategy_selection).and_return(sms_ids)
      subjects = subject.selected_subjects
      expect(ordered_sms.map(&:subject_id)).to eq(subjects.map(&:id))
    end
  end
end
