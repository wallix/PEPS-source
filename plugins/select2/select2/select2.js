/** @opaType Select2.Private.options */
/** @opaType Select2.item */
/** @opaType list('a) */

/**
 * List conversion. Since the version provided in BslNativeLib.js is server
 * side only, we need this implementation.
 */
function arrayOfList(xs) {
  var a = [], tl = xs, hd = xs.hd;
  while (hd) {
    a.push(hd);
    tl = tl.tl;
    hd = tl.hd;
  }
  return a;
}

/** Format ajax parameters. */
function formatAjax(ajax) {
  return {
    url: ajax.url,
    delay: ajax.delay,
    cache: ajax.cache,
    dataType: 'json',
    minimumInputLength: ajax.minimumInputLength,
    // Formatting.
    data: function (params) {
      return { q: params.term, page: params.page };
    },
    processResults: function (data, page) {
      return { results: data.items };
    }
  };
}

/** Transform input options to fit select2 expected format. */
function formatOptions(opts) {
  var options = {
    'minimumResultsForSearch': opts.minimumResultsForSearch,
    'tokenSeparators': arrayOfList(opts.tokenSeparators)
  };

  if (opts.tags) options.tags = true;
  if (opts.allowClear) options.allowClear = true;
  if (opts.multiple) options.multiple = true;
  if (opts.placeholder.string) options.placeholder = opts.placeholder.string;
  if (opts.placeholder.item) options.placeholder = opts.placeholder.item;
  if (opts.data.ajax) options.ajax = formatAjax(opts.data.ajax);
  if (opts.data.array) options.data = arrayOfList(opts.data.array);
  // The empty option is also passed to this function, so we must
  // check the id first to avoid type errors.
  if (opts.templateResult.some)
    options.templateResult = function (item) {
      if (!item.id) item.id = '';
      return $(opts.templateResult.some(item));
    };
  if (opts.templateSelection.some)
    options.templateSelection = function (item) {
      if (!item.id) item.id = '';
      return $(opts.templateSelection.some(item));
    };

  return options;
}


/**
 * @register {string, Select2.Private.options -> void}
 */
function init(sel, options) {
  $(sel).select2(formatOptions(options));
}

/**
 * @register {string -> opa[list(string)]}
 */
function getSelection(sel) {
  var itemList = {nil: {}}, dom = $(sel);
  if (dom && dom.select2) {
    var items = dom.val();
    if (items instanceof Array)
      items.forEach(function (item) {
        itemList = {hd: item, tl: itemList};
      });
    else if (items)
      itemList = {hd: items, tl: itemList};
  }
  return itemList;
}

/**
 * @register {string, opa[list(string)] -> void}
 */
function setSelection(sel, items) {
  var dom = $(sel);
  if (dom && dom.select2)
    dom.val(arrayOfList(items)).trigger('change');
}
