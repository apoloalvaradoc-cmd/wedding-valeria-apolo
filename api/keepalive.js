// Supabase free pausa el proyecto tras ~7 días sin tráfico. El cron de
// vercel.json llama aquí una vez al día y esto hace una búsqueda vacía.
//
// Solo devuelve el código HTTP, nunca la respuesta: el buscador regresa
// nombres de invitados. Borrar (junto con el cron) después del 7 nov.

const SUPABASE_URL = "https://psmaynxnphbfbtayzaeb.supabase.co";
// La misma key pública que va en index.html.
const SUPABASE_KEY = "sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-";

module.exports = async (req, res) => {
  let status = 0;
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/buscar_invitado`, {
      method: "POST",
      headers: { apikey: SUPABASE_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ q: "zzzz" }),
    });
    status = r.status;
  } catch (e) {
    status = 0;
  }
  res.setHeader("Cache-Control", "no-store");
  res.status(status === 200 ? 200 : 502).json({ supabase: status });
};
