module Layered
  module Resource
    # Renders one crumb of a layered resource's breadcrumb trail.
    #
    # `l_ui_breadcrumb_item` marks every unlinked crumb as
    # aria-current="page", which is only correct for the crumb that *is* the
    # current page. A derived trail routinely carries unlinked crumbs that
    # aren't - a parent record with no show route, an unlinked
    # `root_breadcrumb` - so only the crumb a view flags as `current:` is
    # passed through unlinked; the rest render as plain, uncurrent text.
    module BreadcrumbsHelper
      def layered_breadcrumb_item(label, path = nil, current: false)
        return l_ui_breadcrumb_item(label, current ? nil : path) if path || current

        tag.li(tag.span(label), class: "l-ui-breadcrumbs__item")
      end
    end
  end
end
