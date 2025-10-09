// supabase/functions/submit-report/index.ts
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ※ SUPABASE_* は予約語なので使わない。
// secrets は PROJECT_URL / SERVICE_ROLE_KEY / REPORT_TOKEN で受け取る。
const SUPABASE_URL = Deno.env.get("PROJECT_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;
const REPORT_TOKEN = Deno.env.get("REPORT_TOKEN")!; // クライアントと共有するシークレット

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const REASONS = new Set(["spam", "hate", "nsfw", "illegal", "privacy", "other"]);
const isUUID = (s: string) => /^[0-9A-Fa-f-]{36}$/.test(s);

serve(async (req) => {
  try {
    // シークレットヘッダで直叩き防止
    const token = req.headers.get("X-Report-Token");
    if (!token || token !== REPORT_TOKEN) {
      return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
    }
    if (req.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    const { poll_id, reporter_user_id, reason_code, reason_text } = await req.json();

    // 入力チェック
    if (!isUUID(poll_id) || !isUUID(reporter_user_id)) {
      return new Response(JSON.stringify({ error: "invalid uuid" }), { status: 400 });
    }
    if (!REASONS.has(String(reason_code))) {
      return new Response(JSON.stringify({ error: "invalid reason" }), { status: 400 });
    }
    const detail = typeof reason_text === "string" ? reason_text.slice(0, 300) : null;

    // INSERT（ユニーク制約 (poll_id, reporter_user_id) はDB側）
    const { error } = await supabase
      .from("reports")
      .insert({ poll_id, reporter_user_id, reason_code, reason_text: detail });

    // 重複（unique violation）は成功扱い
    if (error && error.code === "23505") {
      return new Response(JSON.stringify({ status: "ok_already_reported" }), { status: 200 });
    }
    if (error) {
      console.error(error);
      return new Response(JSON.stringify({ error: "insert_failed" }), { status: 500 });
    }

    return new Response(JSON.stringify({ status: "ok" }), { status: 201 });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400 });
  }
});