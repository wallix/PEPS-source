/**
 * @register {string, string -> void}
 */
function treeview(dom, roots, callback) {
  roots = JSON.parse(options)
  data = {data: roots, onNodeSelected: callback}
  $(dom).treeview(data);
}

/**
 * @register {string -> void}
 */
function remove(dom) {
  $(dom).treeview('remove');
}
