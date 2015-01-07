require 'spec_helper'

describe Project, :type => :model do
  let(:project) { build(:project) }
  let(:owned) { project }
  let(:not_owned) { build(:project, owner: nil) }
  let(:subject_relation) { create(:project_with_subjects) }
  let(:activatable) { project }
  let(:translatable) { create(:project_with_contents) }
  let(:primary_language_factory) { :project }
  let(:locked_factory) { :project }
  let(:locked_update) { {display_name: "A Different Name"} }
  it_behaves_like "optimistically locked"

  it_behaves_like "is ownable"
  it_behaves_like "has subject_count"
  it_behaves_like "activatable"
  it_behaves_like "is translatable"

  it "should have a valid factory" do
    expect(project).to be_valid
  end

  it 'should require unique names for an ower' do
    owner = create(:user)
    expect(create(:project, name: "hi_fives", owner: owner)).to be_valid
    expect(build(:project, name: "hi_fives", owner: owner)).to_not be_valid
  end

  it 'should not require name uniquenames between owners' do
    expect(create(:project, name: "test_project", owner: create(:user))).to be_valid
    expect(create(:project, name: "test_project", owner: create(:user))).to be_valid
  end

  it 'should require unique displays name for an owner' do
    owner = create(:user)
    expect(create(:project, display_name: "hi fives", owner: owner)).to be_valid
    expect(build(:project, display_name: "hi fives", owner: owner)).to_not be_valid
  end

  it 'should not require display name uniquenames between owners' do
    expect(create(:project, display_name: "test project", owner: create(:user))).to be_valid
    expect(create(:project, display_name: "test project", owner: create(:user))).to be_valid
  end

  describe "links" do
    let(:user) { ApiUser.new(create(:user)) }

    it "should allow workflows to link when user has update permissions" do
      expect(Project).to link_to(Workflow).given_args(user)
                          .with_scope(:scope_for, :update, user)
    end

    it "should allow subject_sets to link when user has update permissions" do
      expect(Project).to link_to(SubjectSet).given_args(user)
                          .with_scope(:scope_for, :update, user)
    end

    it "should allow subjects to link when user has update permissions" do
      expect(Project).to link_to(Subject).given_args(user)
                          .with_scope(:scope_for, :update, user)
    end

    it "should allow collections to link user has show permissions" do
      expect(Project).to link_to(Collection).given_args(user)
                          .with_scope(:scope_for, :show, user)
    end
  end

  describe "#workflows" do
    let(:project) { create(:project_with_workflows) }

    it "should have many workflows" do
      expect(project.workflows).to all( be_a(Workflow) )
    end
  end

  describe "#subject_sets" do
    let(:project) { create(:project_with_subject_sets) }

    it "should have many subject_sets" do
      expect(project.subject_sets).to all( be_a(SubjectSet) )
    end
  end

  describe "#classifications" do
    let(:relation_instance) { project }

    it_behaves_like "it has a classifications assocation"
  end

  describe "#classifcations_count" do
    let(:relation_instance) { project }

    it_behaves_like "it has a cached counter for classifications"
  end

  describe "#subjects" do
    let(:relation_instance) { project }

    it_behaves_like "it has a subjects association"
  end

  describe "#project_roles" do
    let!(:preferences) do
      [create(:access_control_list, resource: project, roles: []),
       create(:access_control_list, resource: project, roles: ["tester"]),
       create(:access_control_list, resource: project, roles: ["collaborator"])]
    end

    it 'should include models with assigned roles' do
      expect(project.project_roles).to include(*preferences[1..-1])
    end

    it 'should not include models without assigned roles' do
      expect(project.project_roles).to_not include(preferences[0])
    end
  end

  describe "#expert_classifier_level and #expert_classifier?" do
    let(:project_user) { create(:user) }
    let(:roles) { [] }
    let(:prefs) do
      create(:access_control_list, user_group: project_user.identity_group,
                                   resource: project,
                                   roles: roles)
    end

    before(:each) do
      prefs
    end

    context "when they are the project owner" do

      it '#expert_classifier_level should be :owner' do
        expect(project.expert_classifier_level(project.owner)).to eq(:owner)
      end

      it "#expert_classifier? should be truthy" do
        expect(project.expert_classifier?(project.owner)).to be_truthy
      end
    end

    context "when they are a project expert" do
      let!(:roles) { ["expert"] }

      it '#expert_classifier_level should be :expert' do
        expect(project.expert_classifier_level(project_user)).to eq(:expert)
      end

      it "#expert_classifier? should be truthy" do
        expect(project.expert_classifier?(project_user)).to be_truthy
      end
    end

    context "when they are an owner and they have marked themselves as a project expert" do
      let!(:project_user) { project.owner }
      let!(:roles) { ["expert"] }

      it '#expert_classifier_level should be :owner' do
        expect(project.expert_classifier_level(project_user)).to eq(:owner)
      end

      it "#expert_classifier? should be truthy" do
        expect(project.expert_classifier?(project_user)).to be_truthy
      end
    end

    context "when they are a project collaborator" do
      let!(:roles) { ["collaborator"] }

      it '#expert_classifier_level should be nil' do
        expect(project.expert_classifier_level(project_user)).to be_nil
      end

      it "#expert_classifier? should be falsey" do
        expect(project.expert_classifier?(project_user)).to be_falsey
      end
    end

    context "when they have no role on the project" do

      it '#expert_classifier_level should be nil' do
        expect(project.expert_classifier_level(project_user)).to be_nil
      end

      it "#expert_classifier? should be falsey" do
        expect(project.expert_classifier?(project_user)).to be_falsey
      end
    end
  end
end
