-- Deprecated compatibility wrapper.
-- Keep this module so older imports continue to work.

local ui_circle_of_fifths = require("lib.ui.ui_circle_of_fifths")

local ui_circle_widget = {}

function ui_circle_widget.draw(ctx, state)
	return ui_circle_of_fifths.draw(ctx, state)
end

return ui_circle_widget
