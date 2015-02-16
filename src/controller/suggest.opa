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


package com.mlstate.webmail.controller

module SuggestController {

// FIXME publish @async w/ callbacks

	server function get_by_label(id) {
		state = Login.get_state()
		if (Login.is_admin(state)) {
			Suggest.get_by_label(id)
		} else Iter.empty
	}

	server function get(id) {
		state = Login.get_state()
		if (Login.is_admin(state))
			Suggest.get(id)
		else none
	}

	server function save(Suggest.suggestion suggestion) {
		state = Login.get_state()
		if (Login.is_admin(state))
			Suggest.add(suggestion)
		else false
	}

	server function delete(id) {
		state = Login.get_state()
		if (Login.is_admin(state))
			Suggest.delete(id)
		else false
	}

}
