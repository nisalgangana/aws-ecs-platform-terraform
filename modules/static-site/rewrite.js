// viewer-request
// 1. www.<domain> -> 301 https://<domain> (path and query string kept)
// 2. Pretty URLs to the files Next.js static export produces:
//    /         -> /index.html
//    /about    -> /about.html
//    /dealers/ -> /dealers/index.html
//    Paths with a dot (/_next/..., /img/x.jpg) pass through unchanged.

function queryString(qs) {
  var parts = [];
  for (var key in qs) {
    var p = qs[key];
    if (p.multiValue) {
      p.multiValue.forEach(function (v) { parts.push(key + '=' + v.value); });
    } else {
      parts.push(key + '=' + p.value);
    }
  }
  return parts.length ? '?' + parts.join('&') : '';
}

function handler(event) {
  var request = event.request;
  var host = request.headers.host ? request.headers.host.value : '';

  if (host.indexOf('www.') === 0) {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: {
        location: { value: 'https://' + host.substring(4) + request.uri + queryString(request.querystring) }
      }
    };
  }

  var uri = request.uri;
  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
  } else if (!uri.includes('.')) {
    request.uri = uri + '.html';
  }
  return request;
}