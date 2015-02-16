/** @opaType Dom.event */
/** @opaType Treeview.node */
/** @opaType Treeview.options */


/**
 * @register {string, string, (Dom.event, Treeview.node -> void) -> void}
 */
function build(dom, roots, callback) {
  roots = JSON.parse(roots)
  data = {data: roots, onNodeSelected: callback}
  $(dom).treeview(data);
}

/**
 * @register {string, Treeview.options -> void}
 */
function options(dom, options) {
  $(dom).treeview(options);
}

/**
 * @register {string -> void}
 */
function remove(dom) {
  $(dom).treeview('remove');
}

/**
 * @register {string -> option(Treeview.node)}
 */
function getSelectedNode(dom) {
  /**
   * Other option: type the option with opa[..]
   * and use js2option to convert undefined to none.
   */
  var sel;
  function set(selection) { sel = selection; };
  $(dom).treeview('getSelectedNode', [set]);
  return sel;
}
