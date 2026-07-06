// Research tree - tech-tree view: prerequisite connector lines + click-through
// detail popup. Re-runs after every NanoUI update since the framework fully
// replaces #uiContent's markup on each refresh (see nano_state.js onUpdate).

// Persisted across refreshes (the DOM gets torn down and rebuilt every
// auto-update cycle, but this module-level state does not) so a click stays
// open/highlighted through the next periodic refresh instead of snapping shut.
var rtOpenNodeId = null;

function rtDrawLines() {
	var wrap = document.getElementById('rt-tree-wrap');
	var svg = document.getElementById('rt-lines');
	if (!wrap || !svg) return;

	svg.innerHTML = '';
	// Explicit width AND height attributes (not just CSS width:100%) so the
	// SVG's internal coordinate space is 1:1 with real pixels. Without this,
	// an SVG with no viewBox defaults to a 300-unit-wide coordinate space
	// that then gets stretched by the browser to fill the CSS width, which
	// silently distorts every x-coordinate we compute below.
	svg.setAttribute('width', wrap.scrollWidth);
	svg.setAttribute('height', wrap.scrollHeight);

	var nodes = wrap.querySelectorAll('.rt-node[data-id]');
	var byId = {};
	for (var i = 0; i < nodes.length; i++) {
		byId[nodes[i].getAttribute('data-id')] = nodes[i];
	}

	var wrapRect = wrap.getBoundingClientRect();

	for (var j = 0; j < nodes.length; j++) {
		var child = nodes[j];
		var prereqAttr = child.getAttribute('data-prereqs');
		if (!prereqAttr) continue;
		var prereqIds = prereqAttr.split(',');
		for (var k = 0; k < prereqIds.length; k++) {
			var parent = byId[prereqIds[k]];
			if (!parent) continue;

			var pr = parent.getBoundingClientRect();
			var cr = child.getBoundingClientRect();

			// Line runs from the END (right edge) of the prerequisite node
			// to the BEGINNING (left edge) of the node that depends on it.
			var x1 = pr.right - wrapRect.left;
			var y1 = pr.top + pr.height / 2 - wrapRect.top;
			var x2 = cr.left - wrapRect.left;
			var y2 = cr.top + cr.height / 2 - wrapRect.top;
			var midX = x1 + (x2 - x1) / 2;

			var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
			path.setAttribute('d', 'M' + x1 + ',' + y1 + ' C' + midX + ',' + y1 + ' ' + midX + ',' + y2 + ' ' + x2 + ',' + y2);
			path.setAttribute('fill', 'none');
			path.setAttribute('stroke', '#8a6d3f');
			path.setAttribute('stroke-width', '1.5');
			path.setAttribute('opacity', '0.55');
			svg.appendChild(path);
		}
	}
}

// Recursively collects every ancestor (prereq, prereq-of-prereq, ...) of
// nodeId that is still locked, so the whole outstanding chain can be lit up.
function rtCollectLockedAncestors(nodeId, visited) {
	visited = visited || {};
	var el = document.querySelector('.rt-node[data-id="' + nodeId + '"]');
	if (!el) return visited;
	var prereqAttr = el.getAttribute('data-prereqs');
	if (!prereqAttr) return visited;
	var ids = prereqAttr.split(',');
	for (var i = 0; i < ids.length; i++) {
		var pid = ids[i];
		if (!pid || visited[pid]) continue;
		visited[pid] = true;
		rtCollectLockedAncestors(pid, visited);
	}
	return visited;
}

function rtClearHighlights() {
	var highlighted = document.querySelectorAll('.rt-ancestor-highlight');
	for (var i = 0; i < highlighted.length; i++) {
		highlighted[i].classList.remove('rt-ancestor-highlight');
	}
}

function rtHighlightChain(nodeId) {
	rtClearHighlights();
	var ancestors = rtCollectLockedAncestors(nodeId);
	for (var id in ancestors) {
		if (!ancestors.hasOwnProperty(id)) continue;
		var el = document.querySelector('.rt-node[data-id="' + id + '"]');
		if (el && el.classList.contains('rt-status-locked')) {
			el.classList.add('rt-ancestor-highlight');
		}
	}
}

function rtOpenDetail(nodeId) {
	var source = document.getElementById('rt-detail-' + nodeId);
	var body = document.getElementById('rt-modal-body');
	var backdrop = document.getElementById('rt-modal-backdrop');
	if (!source || !body || !backdrop) return;

	rtOpenNodeId = nodeId;
	body.innerHTML = source.innerHTML;

	// Copied markup loses any event listeners the framework bound to the
	// original .linkActive element (it re-binds those on its own schedule,
	// not on-demand) -- wire the click ourselves so "Assign" works instantly.
	var links = body.querySelectorAll('.linkActive[data-href]');
	for (var i = 0; i < links.length; i++) {
		(function (el) {
			el.onclick = function (e) {
				e.preventDefault();
				window.location.href = el.getAttribute('data-href');
			};
		})(links[i]);
	}

	backdrop.className = 'rt-open';
	rtHighlightChain(nodeId);
}

function rtCloseDetail() {
	rtOpenNodeId = null;
	var backdrop = document.getElementById('rt-modal-backdrop');
	if (backdrop) backdrop.className = '';
	rtClearHighlights();
}

function rtBindNodes() {
	var nodes = document.querySelectorAll('.rt-node[data-id]');
	for (var i = 0; i < nodes.length; i++) {
		(function (el) {
			el.onclick = function () {
				rtOpenDetail(el.getAttribute('data-id'));
			};
		})(nodes[i]);
	}

	var closeBtn = document.getElementById('rt-modal-close');
	if (closeBtn) closeBtn.onclick = rtCloseDetail;

	var backdrop = document.getElementById('rt-modal-backdrop');
	if (backdrop) {
		backdrop.onclick = function (e) {
			if (e.target === backdrop) rtCloseDetail();
		};
	}
}

function rtRefresh() {
	rtBindNodes();
	// Layout needs a tick to settle (grid reflow) before measuring positions.
	setTimeout(function () {
		rtDrawLines();
		// The periodic auto-update replaces this whole content block, which
		// would otherwise silently snap the modal shut -- restore whatever
		// was open (and its highlight) right after the fresh render lands.
		if (rtOpenNodeId) {
			rtOpenDetail(rtOpenNodeId);
		}
	}, 30);
}

if (typeof NanoStateManager !== 'undefined') {
	NanoStateManager.addAfterUpdateCallback('research_tree', function (data) {
		rtRefresh();
		return data;
	});
}
rtRefresh();
window.addEventListener('resize', rtDrawLines);
