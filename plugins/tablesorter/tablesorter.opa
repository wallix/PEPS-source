package tablesorter

/** Definition of a custom parser. */
type TableSorter.parser = {
  // Unique parser identifier.
  string id,
  // Extraction of the parser sorting value.
  // The more general function has been reduced to an attribute extraction.
  // The first argument is the cell value, the second the attribute to extract.
  { string extract } or // Extract an hidden attribute.
  { (string -> string) transform} // Transform a value.
  format,
  // Type of the extracted value.
  ({numeric} or {text}) ctype
}

client module TableSorter {

  /** Define an custom parser. */
  function addParser(TableSorter.parser custom) {
    (%%tablesorter.addParser%%)(custom)
  }

  /** Initialize a table. */
  function init(dom dom) {
    (%%tablesorter.init%%)(Dom.to_string(dom))
  }

}
