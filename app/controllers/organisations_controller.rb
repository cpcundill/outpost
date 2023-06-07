# This controller lets community users manage their organisations.
class OrganisationsController < ApplicationController
    before_action :no_admins
    before_action :require_not_onboarded, only: [:new, :create]
    before_action :set_organisation, only: [:index, :edit, :update]

    def index
        unless current_user.organisation.present?
            redirect_to new_organisation_path 
        else
            @services = @organisation.services.kept
            @users = @organisation.users.kept
        end
    end

    def new
        @organisation = Organisation.new
    end

    def create
        @organisation = Organisation.new(organisation_params)
        if @organisation.save
            current_user.organisation = @organisation
            current_user.save
            redirect_to organisations_path
        else
            render "new"
        end
    end

    def edit
    end
  
    def update
      if @organisation.update(organisation_params)
        redirect_to organisations_path
      else
        render "edit"
      end
    end

    private

    def organisation_params
        params.require(:organisation).permit(
            :name
        )
    end

    def set_organisation
        @organisation = current_user.organisation
    end

    def require_not_onboarded
        redirect_to organisations_path if current_user.organisation
    end
end
