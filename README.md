# WsProxy

WsProxy is a simple Websocket Proxy that intercepts Websocket text frames. For every intercepted websocket frame a webhook can be called. The HTTP response status of the webhook determines whether the proxy forwards the frame or closes the socket.

The typical deployment scenario of WsProxy is behind a Web Application Firewall (WAF) which (today solutions) usually lacks Websocket scanning capabilities (inbound & outbound). The WsProxy could use the webhooks to send the websocket frame payloads as a standard HTTP request to a designated WAF endpoint for content inspection.

Note: Obviously this has an impact on the WebSocket end to end latencies.

## Configuration

For the moment the proxy configuration is done via HTTP headers that are injected by a proxy or WAf when accepting a Websocket connection. For this reason you shoud **never** expose WsProxy directly to your Websocket clients and always place it behind a proxy or WAF to be in control of the `x-wsproxy-*` headers.

Mandatory headers:
- `x-wsproxy-upstream`: a Websocket endpoint (path and querystring are ignored)

Optional Headers (Webhook):
- `x-wsproxy-inboundhook`: a HTTP url used for the webhook for every inbound Websocket frame
- `x-wsproxy-inboundhook-method`: the HTTP method used for the webhook request, defaults to 'POST'
- `x-wsproxy-inboundhook-headers`: additional HTTP headers used for the webhook requests, format is `header1=val1,header2=val2`
- `x-wsproxy-outboundhook`: a HTTP url used for the webhook for every outbound Websocket frame
- `x-wsproxy-outboundhook-method`: the HTTP method used for the webhook request, defaults to 'POST'
- `x-wsproxy-outboundhook-headers`: additional HTTP headers used for the webhook requests, format is `header1=val1,header2=val2`

Optional Headers (Socket):
- `x-wsproxy-compress`: compress Websocket frames, defaults to 'false'
- `x-wsproxy-idletimeout`: timeout in milliseconds after an idling socket gets closed, defaults to '60000'
- `x-wsproxy-maxframesize`: the max size of a websocket frame in bytes, defaults to '2048'
- `x-wsproxy-validateutf8`: validates utf8 encoding of the frame payload, defaults to 'false'

Other Configuration, in environment variables:
- `WSPROXY_PORT`: the listener port for the websocket proxy, defaults to '4000'
- `WSPROXY_WEBHOOK_POOL_SIZE`: the webhook request pool size, defaults to '100'