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


package com.mlstate.webmail.view

module SuggestView {

function get_type(Suggest.suggestion suggestion) {
	match (suggestion.criterion) {
		case {~keyword, ...}: (true, keyword)
		case {~recipient}: (false, recipient)
	}
}

client function radio_onclick(Dom.event event) {
	void
}

function make_radio(name, classname, checked) { {
	id: name,
	value: name,
	checked: checked,
    text: <span class="label {classname}">{String.capitalize(name)}</span>,
    onclick: some(radio_onclick)
} }

function do_cancel(_) {
	#suggestion_editor = <></>
}

function do_save(current, _) {
	suggestion = get_form(current)
	if (SuggestController.save(suggestion)) {
		 #{"filters-pane"} = display_by_label(current.label_id)
		 #suggestion_editor = edit(current)
	} else {
	 	Notifications.error("Filter", <>{@i18n("Could not save")}</>)
	}
}

function do_delete(current) {
	message = if (SuggestController.delete(current.id)) { AppText.Deleted() } else { @i18n("Could not delete") }
	#{"filters-pane"} = display_by_label(current.label_id)
	#suggestion_editor = <p>{message}</p>
}

function get_form(current) {
	value = Dom.get_value(#suggest_expression)
	criterion = match (Radio.get_checked([#keyword, #recipient], "keyword")) {
		case "recipient": { recipient: value }
		default: { keyword: value, partial: false }
	}
	{ current with criterion: criterion }
}

function delete_action(current, _) {
	if (Client.confirm(@i18n("Are you sure you want to delete this filter?")))
		{ do_delete(current) }
}

function delete_button(current) {
	if (current.id == Suggest.dummy_id) { <></> }
	else {
		<div class="pull-right">
			<a onclick={delete_action(current, _)} class="btn btn-sm btn-default">
				<i class="fa fa-trash-o"/> {AppText.delete()}
			</a>
		</div>
	}
}

function edit(current) {
	(keyword_type, value) = get_type(current)
	Form.wrapper(
	<div class="pane-heading">
		<div class="pull-right">{delete_button(current)}</div>
		<h3>{if (current.id != Suggest.dummy_id) {@i18n("Edit filter")} else {@i18n("Create filter")}}</h3>
	</div> <+>
      Form.line({Form.Default.line with label: @i18n("Expression"), id: "suggest_expression", ~value}) <+>
      Form.label(
        @i18n("Type"), "",
        Radio.list([
          make_radio("keyword", "label-warning-inverse", keyword_type),
          make_radio("recipient", "label-info-inverse", not(keyword_type))
        ])
      ) <+>
      <div class="form-group">
      	{WB.Button.make({button: <>{@i18n("Save changes")}</>, callback: do_save(current, _)}, [{primary}])}
      </div>
    , false)
}

function display_edit(current, _) {
	match (current) {
		case {~some}:
			#suggestion_editor = edit(some)
		default:
			#suggestion_editor = <div class="error">{@i18n("Could not get suggestion content")}</div>
	}
}

function display(Suggest.suggestion suggestion, show_label) {
	action_edit = display_edit(SuggestController.get(suggestion.id), _)
	<li class="list-group-item">
		{
			if (show_label)
				match (Label.get(suggestion.label_id)) {
					case {some: label}: LabelView.display(label)
					default: <></>
				}
			else <></>
		}
		<span class="criterion">
		<div onclick={action_edit}>
		{ match (suggestion.criterion) {
			case {~keyword, ...}:
				<span class="label label-warning-inverse">{@i18n("keyword")}</span>
				<span class="keyword">{keyword}</span>
			case {~recipient}:
				<span class="label label-info-inverse">{@i18n("recipient")}</span>
				<span class="recipient">{recipient}</span>
		}}
		</div>
		</span>
	</li>
}

function display_by_label(label_id) {
	action_new = display_edit(some(Suggest.new(label_id)), _)
	<div id=#suggestion class="suggestions">
	  <div class="col-md-4 pane-inner-left">
	  	<div class="pane-heading">
  			<button type="button" onclick={action_new} class="btn btn-sm btn-default pull-right">
  				<i class="fa fa-plus-circle-o"/> {@i18n("New filter")}
  			</button>
			<h3>Filters</h3>
		</div>
		<ul class="list-group">
		{
		res = SuggestController.get_by_label(label_id)
		res = Iter.map(display(_, false), res)
		Iter.fold(`<+>`, res, <></>)
		}
		</ul>
	  </div>
	  <div id="suggestion_editor" class="col-md-8 pane-inner-right"></div>
	</div>
	}

}
