# Exercises a remote filter: the author options are fetched from an endpoint as
# the user types (`url:`) instead of being rendered up front, so the control is
# a combobox no matter how many users there are. `min_chars:` and the rest of
# COMBOBOX_FILTER_OPTIONS pass straight through to l_ui_combobox.
class RemotePostResource < PostResource
  filters user: { url: -> { user_options_path }, min_chars: 2 },
          status: { as: :select } # declared, so it stays a checkbox list
end
