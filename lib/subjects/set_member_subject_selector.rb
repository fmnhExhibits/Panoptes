module Subjects
  class SetMemberSubjectSelector
    attr_reader :workflow, :user
    SELECT_FIELDS = '"set_member_subjects"."id",' \
    '"set_member_subjects"."random",' \
    '"set_member_subjects"."priority"'

    def initialize(workflow, user)
      @workflow = workflow
      @user = user
    end

    def set_member_subjects
      select_data.select(SELECT_FIELDS)
    end

    private

    def select_data
      if user
        select_data_for_the_user
      else
        select_non_retired
      end
    end

    def select_data_for_the_user
      scope = select_non_retired_unseen_for_user
      if scope.exists?
        scope
      else
        select_unseen_for_user
      end
    end

    def select_non_retired
      SetMemberSubject.non_retired_for_workflow(workflow)
    end

    def select_unseen_for_user
      SetMemberSubject.unseen_for_user_by_workflow(user, workflow)
    end

    def select_non_retired_unseen_for_user
      select_unseen_for_user.merge(select_non_retired)
    end
  end
end
