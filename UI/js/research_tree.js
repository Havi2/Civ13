// Research tree - tech-tree view: prerequisite connector lines + click-through
// detail popup. Re-runs after every NanoUI update since the framework fully
// replaces #uiContent's markup on each refresh (see nano_state.js onUpdate).

function rtDrawLines() {
	var wrap = document.getElementById('rt-tree-wrap');
	var svg = document.getElementById('rt-lines');
	if (!wrap || !svg) return;

	svg.innerHTML = '';
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

function rtOpenDetail(nodeId) {
	var source = document.getElementById('rt-detail-' + nodeId);
	var body = document.getElementById('rt-modal-body');
	var backdrop = document.getElementById('rt-modal-backdrop');
	if (!source || !body || !backdrop) return;

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
}

function rtCloseDetail() {
	var backdrop = document.getElementById('rt-modal-backdrop');
	if (backdrop) backdrop.className = '';
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
	setTimeout(rtDrawLines, 30);
}

if (typeof NanoStateManager !== 'undefined') {
	NanoStateManager.addAfterUpdateCallback('research_tree', function (data) {
		rtRefresh();
		return data;
	});
}
rtRefresh();
window.addEventListener('resize', rtDrawLines);
