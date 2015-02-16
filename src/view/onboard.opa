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

module OnboardView {

	function header(content) {
		<p>Please follow this guide to setup your email and collaboration platform.</p>
		<ol>
		{content}
		</ol>
	}

	function urn_admin(string where) {
		URN.make({admin: where}, [])
	}

	function urn_people(string where) {
		URN.make({people: where}, [])
	}

	function build(state) {
		if (Login.is_admin(state)
			) {
			detect = Onboard.detect_admin(state)
			warning_class =
				if (detect.no_class)
					[<li>Create <a onclick={Content.update_callback(urn_admin("classification"), _)}>security classes</a> to identify and protect confidential information.</li>]
				else []
			warning_user =
				if (detect.no_user)
					[<li>Add users <a onclick={Content.update_callback(urn_people("users"), _)}>manually</a>, in <a onclick={Content.update_callback(urn_admin("bulk"), _)}>bulk</a> or by adding a <a onclick={Content.update_callback(urn_admin("ldap"), _)}>LDAP</a> connection.</li>]
				else []
			warnings = List.flatten([warning_class, warning_user])
			if (warnings == []) none
			else some(header(warnings))
		} else none
	}

}
