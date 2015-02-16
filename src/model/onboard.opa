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



/* checks to add
- admin: user name is still admin
- admin: no_team
 */
package com.mlstate.webmail.model

type Onboard.user =
	{ bool no_message, bool no_file }

type Onboard.admin =
	{ bool no_user, bool no_class, bool unchanged_domain, bool no_license }

module Onboard {

	protected function detect(state) {
		no_message = Message.is_empty(state.key)
		no_file = File.count({some: state.key}) == 0
		~{no_message, no_file}
	}

	protected function detect_admin(state) {
		no_user = User.count([]) == 1
		no_class = List.length(Label.list(User.dummy, {class})) == Label.predefined
		unchanged_domain = Admin.get_domain() == AppConfig.default_domain
		no_license = true
		~{no_user, no_class, unchanged_domain, no_license}
	}

}
