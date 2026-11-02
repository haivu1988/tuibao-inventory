import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ error: "Đăng nhập Quản lý trước." }, 401);
    const url = Deno.env.get("SUPABASE_URL")!;
    const publishable = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY")!;
    const secret = Deno.env.get("APP_SUPABASE_SECRET_KEY");
    if (!secret) return json({ error: "Chưa cấu hình khóa bí mật cho hàm tạo tài khoản." }, 500);

    const callerClient = createClient(url, publishable, { global: { headers: { Authorization: authorization } } });
    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Phiên đăng nhập không hợp lệ." }, 401);
    const { data: profile } = await callerClient.from("profiles").select("role").eq("user_id", userData.user.id).single();
    if (profile?.role !== "manager") return json({ error: "Chỉ Quản lý được tạo tài khoản." }, 403);

    const { username: rawUsername, full_name, branch_id, password } = await req.json();
    const username = String(rawUsername ?? "").trim().toLowerCase();
    if (!/^[a-z0-9._-]{3,32}$/.test(username)) return json({ error: "Tên đăng nhập cần 3–32 ký tự: chữ thường, số, dấu chấm, gạch dưới hoặc gạch ngang." }, 400);
    if (typeof full_name !== "string" || !full_name.trim()) return json({ error: "Cần nhập tên nhân viên." }, 400);
    if (typeof password !== "string" || password.length < 8) return json({ error: "Mật khẩu cần ít nhất 8 ký tự." }, 400);
    const { data: branch } = await callerClient.from("branches").select("id").eq("id", branch_id).maybeSingle();
    if (!branch) return json({ error: "Chi nhánh không tồn tại." }, 400);

    const admin = createClient(url, secret, { auth: { autoRefreshToken: false, persistSession: false } });
    const email = `${username}@tuibao.invalid`;
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { full_name: full_name.trim() },
    });
    if (createError || !created.user) return json({ error: createError?.message ?? "Không tạo được tài khoản." }, 400);
    const { error: profileError } = await admin.from("profiles").insert({
      user_id: created.user.id, username, full_name: full_name.trim(), role: "staff", branch_id,
    });
    if (profileError) {
      await admin.auth.admin.deleteUser(created.user.id);
      return json({ error: profileError.message }, 400);
    }
    return json({ user_id: created.user.id, username, full_name: full_name.trim(), branch_id });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Có lỗi khi tạo tài khoản." }, 500);
  }
});
