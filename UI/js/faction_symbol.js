// Faction symbol editor -- binds the 32x32 pixel grid's click handling.
// Paint/bucket toggle and the toolbar buttons reuse the framework's own
// .linkActive markup (rebound automatically by nano_base_callbacks.js), but
// the 1024 individual pixel cells are plain divs (helper.link() isn't a good
// fit for a colored square with no icon/text) -- their clicks are bound and
// rebound here, same rationale as research_tree.js: every update fully
// replaces the DOM, so bindings from the previous render are gone each time.

function fsBindCells() {
	var cells = document.querySelectorAll('.fs-cell');
	for (var i = 0; i < cells.length; i++) {
		(function (el) {
			el.onclick = function () {
				var x = el.getAttribute('data-x');
				var y = el.getAttribute('data-y');
				window.location.href = NanoUtility.generateHref({ paint: 1, x: x, y: y });
			};
		})(cells[i]);
	}
}

if (typeof NanoStateManager !== 'undefined') {
	NanoStateManager.addAfterUpdateCallback('faction_symbol', function (data) {
		fsBindCells();
		return data;
	});
}
fsBindCells();
