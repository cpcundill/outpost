class Admin::BaseController < ApplicationController
    before_action :require_admin!
    before_action :set_counts, if: :should_count?

    private

    def require_admin!
        unless current_user.admin === true
            redirect_to root_path
        end
    end

    def should_count?
        controller_name === "services" || "requests"
    end

    def set_counts
        @all_count = Service.kept.count
        @ofsted_count = Service.kept.ofsted_registered.count
        @pending_count = Service.kept.where(approved: nil).count
        @archived_count = Service.discarded.count
    end
end