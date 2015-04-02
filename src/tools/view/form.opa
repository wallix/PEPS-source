/*
 * PEPS is a modern collaboration server
 * Copyright (C) 2015 MLstate
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


package com.mlstate.webmail.tools.view

/**
 * Construction of generic input components, composed of:
 *   - an input field
 *   - an kind selector
 * Given the id of the component, the id of the input field
 * is ['{id}-input'], and of the kind selector ['{id}-kind'].
 * The kind selector is built as a dropdown menu, whose items
 * must be provided in the options.
 *
 * It it possible to group identical input components into groups. The group
 * includes a label, and has an action to add more inputs.
 */

type Form.input = {
  string id,
  string label,  // Used as placeholder for the input.
  list(string) kinds,
  { string kind, option(string) input } defaults
}

type Form.group = {
  string id,
  string label,
  list(string) kinds,
  bool addnew,   // Add a new input on creation.
  { string kind, list(Form.input) inputs } defaults
}

/**
 * Options of an single input line.
 */

type Form.line = {
	string id,
	string label,
	list(string) class,
	string value,
	string typ,
	option(Dom.event -> void) action,
	bool display,
  bool required
}

module Form {

	private function const(x)(_) { x }

	/** {2} Rendering of input components. */

	/** Render an input line. */
  both function input(Form.input options) {
  	// Actions.
    function remove_input(_) { Dom.remove(#{options.id}) }
    // Input.
    <div class="multiple-input" id="{options.id}">
      <a onclick={remove_input} class="pull-right" title={@intl("Remove")} data-placement="bottom" rel="tooltip" ><i class="fa fa-minus-circle-o"/></a>
      <div class="input-group">
        <div class="input-group-btn">
          { Misc.chooser({
              id: "{options.id}-kind",
              options: options.kinds,
              placeholder: options.defaults.kind,
              custom: false, onselect: none
          }) }
        </div>
        { match (options.defaults.input) {
            case {some: value}: <input id="{options.id}-input" class="form-control" value="{value}"/>
            default: <input id="{options.id}-input" class="form-control" placeholder="{options.label}"/>
          } }
      </div>
    </div>
  }

  /** {2} Render an input group. */

  /** Append a new input line at the end of the group. */
  client function add_input(options) {
    id = Dom.fresh_id()
    input = Form.input(~{
    	id, kinds: options.kinds, label: options.label,
      defaults: { kind: options.defaults.kind, input: none }
    })
    #{"{options.id}-inputs"} += input
  }

  /** Render an input group. */
  both function group(Form.group options) {
    if (options.defaults.inputs == [] && not(options.addnew)) <></>
    else {
      inputs = List.fold(function (input, acc) { acc <+> Form.input(input) }, options.defaults.inputs, <></>)
      new =
       (if (options.addnew)
          Form.input(~{
            id: Dom.fresh_id(), kinds: options.kinds, label: options.label,
            defaults: { kind: options.defaults.kind, input: none } })
        else <></>)
      <div class="form-group" id="{options.id}">
        <label class="control-label">{options.label}</label>
        <a onclick={function (_evt) { add_input(options) }} class="fa fa-plus-circle-o"></a>
        <div id="{options.id}-inputs">{inputs}{new}</div>
      </div>
    }
  }

  /** {2} Line rendering. */

  /** Render a single input line. */
  both function line(Form.line options) {
    action = options.action ? const(void)
    input =
      <input id="{options.id}" type="{options.typ}" class="form-control {options.class}" autocomplete="off"
          value={options.value} onnewline={action}></input> |>
      (if (options.required) Xhtml.add_attribute_unsafe("required", "required", _) else identity)
    content = <><label class="control-label" for="{options.id}">{options.label}</label>{input}</>
    if (options.display) <div id="{options.id}-form-group" class="form-group">{content}</div>
    else  							 <div id="{options.id}-form-group" class="form-group" style="display:none">{content}</div>
  }

  /* Horizontal form line */
  both function hr_line(Form.line options) {
    action = options.action ? const(void)
    input =
      <input id="{options.id}" type="{options.typ}" class="form-control {options.class}" autocomplete="off"
          value={options.value} onnewline={action}></input> |>
      (if (options.required) Xhtml.add_attribute_unsafe("required", "required", _) else identity)
    content = <><label class="control-label col-sm-2" for="{options.id}">{options.label}</label><div class="col-sm-10">{input}</div></>
    if (options.display) <div id="{options.id}-form-group" class="form-group">{content}</div>
    else                 <div id="{options.id}-form-group" class="form-group" style="display:none">{content}</div>
  }

	/** Wrap a list of inputs under a form component. */
  both function wrapper(content, stacked) {
    class = if (stacked) ["form-horizontal"] else []
    <form role="form" method="post" class={class} action="javascript:void(0)">{content}</form>
  }

  /** Add a label to an existing input component. */
  both function label(label, id, input) {
    <div class="form-group">
      <label class="control-label" for="{id}">{label}</label>
      {input}
    </div>
  }

  /** Add a form-group to an existing input component. */
  both function form_group(input) {
    <div class="form-group">
      {input}
    </div>
  }

  /** Label for horizontal form */
  both function hr_label(label, id, input) {
    <div class="form-group">
      <label class="control-label col-sm-2" for="{id}">{label}</label>
      <div class="col-sm-10">{input}</div>
    </div>
  }

  /** Label for horizontal form */
  both function hr_static(label, text) {
    <div class="form-group">
      <label class="control-label col-sm-2">{label}</label>
      <div class="col-sm-10">
        <p class="form-control-static">{text}</p>
      </div>
    </div>
  }

  /* Button for */
  both function hr_btn(btn) {
    <div class="form-group">
      <div class="col-sm-offset-2 col-sm-10">
        {btn}
      </div>
    </div>
  }

  /** {2} Default values for each component. */

  module Default {
  	both line = {
  		id: "", class: [],
  		label: "", action: none,
			value: "", display: true,
			typ: "text", required: false
  	}
  } // END DEFAULT

}
