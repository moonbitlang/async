// https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_a_WebSocket_server_in_JavaScript_Deno
Deno.serve({
    port: 8080,
    handler(request) {
        if (request.headers.get("upgrade") !== "websocket") {
            return new Response(null, { status: 200 });
        }
        const { socket, response } = Deno.upgradeWebSocket(request);
        socket.onopen = () => {
            console.log("CONNECTED");
        };
        socket.onmessage = (event) => {
            console.log("MESSAGE RECEIVED: ", event.data);
            socket.send("pong");
        };
        socket.onclose = () => console.log("DISCONNECTED");
        socket.onerror = (err) => console.error("ERROR: ", err);
        return response;
    },
});
