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


package com.mlstate.webmail.model

abstract type Suggest.id = DbUtils.oid

type Suggest.criterion =
	{ string keyword, bool partial } or { string recipient }

type Suggest.suggestion =
	{ Suggest.id id,
	  Suggest.criterion criterion,
	  int label_id,
	  int priority,
	  option(Date.date) deleted
	}

database Suggest.suggestion /webmail/suggest[{id}]
database /webmail/suggest[_]/criterion = { recipient: "" }
database /webmail/suggest[_]/criterion/partial = { false }

module Suggest {

	Suggest.id dummy_id = ""

	function Suggest.suggestion new(label_id) { {
		id: "", // == DbUtils.OID.dummy
		criterion: { keyword: "", partial: false },
		label_id: label_id,
		priority: 1,
		deleted: none
	} }

	function create(Suggest.suggestion suggestion) {
		id = DbUtils.OID.gen()
		{ suggestion with id: id }
	}

	function add(Suggest.suggestion suggestion) {
		suggestion =
			if (suggestion.id == "") Suggest.create(suggestion)
			else suggestion
		/webmail/suggest[id == suggestion.id] <- suggestion
		true
	}

	function get_by_label(int id) {
		DbSet.iterator(/webmail/suggest[label_id == id and deleted == {none}; order +criterion])
	}

	function get(Suggest.id id) {
		?/webmail/suggest[id == id]
	}

	function delete(Suggest.id id) {
		@catch(Utils.const(false), {
			Db.remove(@/webmail/suggest[id == id]/deleted)
			/webmail/suggest[id == id]/deleted <- some(Date.now())
			true
		})
	}

	function option(int) test(Suggest.suggestion suggestion, recipients, words) {
		res = match (suggestion.criterion) {
			case { ~keyword, ~partial }:
				StringSet.contains(keyword, words)
			case { ~recipient }:
				List.exists(String.contains(_, recipient), recipients)
		}
		if (res) {some: suggestion.label_id}
		else {none}
	}

	function option(int) first_result(iter it) {
		iter it = Iter.skip_while(Option.is_none, it)
		match (it.next()) {
			case {some: ({some: elt}, _)}: {some: elt}
			default: {none}
		}
	}

	private function get_words(string str) {
	  word_char = parser { case c=[a-zA-Z0-9_]: c; }
	  sep = parser { case (!word_char .)*: void; }
	  alphanum = parser { case w=(word_char+) sep: w; }
	  explode = parser { case sep ws=alphanum*: ws; }
	  match (Parser.try_parse(explode, str)) {
		  case {some:words}: List.map(Text.to_string,words)
		  case {none}: [];
	  }
	}

	server function make(mailto, mailcontent) {
		words = List.map(String.lowercase, get_words(mailcontent))
		words = StringSet.From.list(words)
		emails = List.map(Message.Address.to_string, mailto)
		// FIXME: use controller
		crits = DbSet.iterator(/webmail/suggest[deleted == {none}; order +priority])
		labels = Iter.map(test(_, emails, words), crits)
		first_result(labels)
	}

}
