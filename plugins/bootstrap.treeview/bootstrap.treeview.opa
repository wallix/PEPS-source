package bootstrap.treeview

/**
 * Type of tree nodes.
 */
 // Leaves: necessary so that the 'nodes' field remains undefined
type Treeview.node = {
  string text,
  list(string) tags,
  // Additional information.
  string identifier,
  string description
} or
 // Node with children.
{
  string text,
  list(Treeview.node) nodes,
  list(string) tags,
  // Additional information.
  string identifier,
  string description
}

/**
 * Additional treeview global options.
 */
type Treeview.options = {
  string expandIcon,
  string collapseIcon
}

module Treeview {

  protected function Treeview.node internal(string identifier, string text, string description, list(Treeview.node) nodes) {
    /*base = ~{ default_node with identifier, text}
    internal = { base extend ~nodes }
    internal*/
    ~{ text, identifier, nodes, description, tags: [] }
  }

  protected function Treeview.node leaf(identifier, text, description) {
    ~{ identifier, text, description, tags: [] }
  }

  protected function Treeview.node node(identifier, text, description, nodes) {
    match (nodes) {
      case []: ~{ identifier, text, description, tags: [] }
      default: ~{ text, identifier, nodes, description, tags: [] }
    }
  }

  /**
   * Necessary accessors.
   */
  function text(Treeview.node node) {
    match (node) {
      case {nodes:_, ~text ...}
      case {~text ...}: text
    }
  }
  function identifier(Treeview.node node) {
    match (node) {
      case {nodes:_, ~identifier ...}
      case {~identifier ...}: identifier
    }
  }
  function description(Treeview.node node) {
    match (node) {
      case {nodes:_, ~description ...}
      case {~description ...}: description
    }
  }

  client function build(dom dom, list(Treeview.node) roots, (Dom.event, Treeview.node -> void) callback) {
    ser = OpaSerialize.serialize(roots)
    (%%treeview.build%%)(Dom.to_string(dom), ser, callback)
  }

  /**
   * Same as [treeview], with the argument previously serialized.
   * Using OpaSerialize.serialize, lists are correctly rendered as [x1 .. xn] instead of {hd: _, tl:} and {nil}.
   */
  client function build_serialized(dom dom, string roots, (Dom.event, Treeview.node -> void) callback) {
    (%%treeview.build%%)(Dom.to_string(dom), roots, callback)
  }

  client function options(dom dom, Treeview.options options) {
    (%%treeview.options%%)(Dom.to_string(dom), options)
  }

  /**
   * Return the current selection.
   */
  client function selected_node(dom dom) {
    (%%treeview.getSelectedNode%%)(Dom.to_string(dom))
  }
}
