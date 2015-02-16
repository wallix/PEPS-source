package html2text

type HtmlToText.options = {
	// Defines after how many chars a line break should follow in p elements.
	int wordwrap,
	// Allows to select certain tables by the class or id attribute from the HTML document.
	// This is necessary because the majority of HTML E-Mails uses a table based layout.
	// Prefix your table selectors with an . for the class and with a # for the id attribute.
	// All other tables are ignored.
	{all} or {list(string) select} tables
}

module HtmlToText {

	defaults = {
		wordwrap: 80,
		tables: {select: []}
	}

	/** Convert a mail html content to prettified text. */
	function convert(string html, HtmlToText.options options) {
		%%Html2text.html2text%%(html, options)
	}

}