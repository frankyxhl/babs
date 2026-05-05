import { Socket } from "./phoenix.mjs";
import { LiveSocket } from "./phoenix_live_view.esm.js";

const token = document.querySelector("meta[name='csrf-token']")?.content || "";
const liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: token } });

liveSocket.connect();
window.liveSocket = liveSocket;
