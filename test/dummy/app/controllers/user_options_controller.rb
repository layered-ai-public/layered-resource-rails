# Options endpoint for a remote combobox filter (see RemotePostResource). It's
# an ordinary controller action in the host app, authorised however any index
# would be — the gem never routes it, the resource just points a filter at it.
class UserOptionsController < ApplicationController
  include Layered::Ui::ComboboxOptions

  def index
    render json: l_ui_combobox_options(User.all, label: :name, search: [:name, :email])
  end
end
