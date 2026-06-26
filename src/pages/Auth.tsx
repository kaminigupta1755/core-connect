import { useNavigate, Link } from "react-router-dom";
import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Toaster } from "@/components/ui/sonner";
import {
  Zap, Mail, Lock, User as UserIcon, Phone, Eye, EyeOff, ShieldCheck,
  QrCode, KeyRound, Activity, Mic, Globe2, Users, Building2,
  Briefcase, Code2, HeartHandshake, TrendingUp, CircleDot, ArrowRight,
  ChevronLeft, ChevronRight, Headphones, Languages,
} from "lucide-react";
import aiIdle from "@/assets/vnc/ai-idle.png";
import aiPassword from "@/assets/vnc/ai-password.png";
import aiError from "@/assets/vnc/ai-error.png";
import aiProcessing from "@/assets/vnc/ai-processing.png";
import aiSuccess from "@/assets/vnc/ai-success.png";
import aiHelp from "@/assets/vnc/ai-help.png";


type AIState = "idle" | "email" | "password" | "peek" | "processing" | "success" | "error" | "recovery";

const stateMeta: Record<AIState, { img: string; title: string; msg: string; tone: string }> = {
  idle:       { img: aiIdle,       title: "Hello! I'm Nexus AI",     msg: "Welcome back. I'll guide you through a secure sign-in.",     tone: "text-primary" },
  email:      { img: aiIdle,       title: "Listening…",                msg: "Enter your enterprise email. I'll resolve your identity.",   tone: "text-primary" },
  password:   { img: aiPassword,   title: "Privacy mode on",           msg: "Your credentials are private. My eyes are closed.",          tone: "text-primary" },
  peek:       { img: aiHelp,       title: "Visibility on",             msg: "Verify your entry — toggle privacy back when ready.",        tone: "text-primary" },
  processing: { img: aiProcessing, title: "Verifying credentials…",    msg: "Negotiating secure handshake and routing your role.",        tone: "text-primary" },
  success:    { img: aiSuccess,    title: "Welcome back, Boss!",       msg: "Identity confirmed. Preparing your dashboard.",              tone: "text-emerald-400" },
  error:      { img: aiError,      title: "Oh no! Login failed.",      msg: "Please verify your credentials and try again.",              tone: "text-destructive" },
  recovery:   { img: aiHelp,       title: "I'm here to help",          msg: "Enter your email and I'll send a secure reset link.",        tone: "text-primary" },
};

const opportunities = [
  { icon: Code2,         title: "Developer",        lines: ["Build enterprise products", "Work on global projects", "AI-powered development"] },
  { icon: Users,         title: "Reseller",         lines: ["High commissions", "Global territory", "Recurring revenue"] },
  { icon: Building2,     title: "Franchise Owner",  lines: ["Regional rights", "Local market control", "Proven playbooks"] },
  { icon: HeartHandshake,title: "Partner",          lines: ["Co-sell with us", "Shared pipeline", "Strategic accounts"] },
  { icon: TrendingUp,    title: "Sales Executive",  lines: ["Uncapped commissions", "Enterprise deals", "Career growth"] },
  { icon: Briefcase,     title: "Support Executive",lines: ["Help millions of users", "24/7 global desk", "Customer success"] },
];

function AuthPage() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [tab, setTab] = useState<"email" | "username" | "mobile" | "otp" | "qr">("email");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [showPwd, setShowPwd] = useState(false);
  const [remember, setRemember] = useState(true);
  const [busy, setBusy] = useState(false);
  const [aiState, setAiState] = useState<AIState>("idle");
  const [voiceOn, setVoiceOn] = useState(false);
  const [oppIndex, setOppIndex] = useState(0);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) navigate("/me");
    });
  }, [navigate]);

  useEffect(() => {
    if (showPwd && aiState === "password") setAiState("peek");
    else if (!showPwd && aiState === "peek") setAiState("password");
  }, [showPwd, aiState]);

  useEffect(() => {
    const t = setInterval(() => setOppIndex((i) => (i + 1) % opportunities.length), 4500);
    return () => clearInterval(t);
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setAiState("processing");
    try {
      if (mode === "signup") {
        const { error } = await supabase.auth.signUp({
          email, password,
          options: {
            emailRedirectTo: `${window.location.origin}/me`,
            data: { display_name: name || email.split("@")[0], phone },
          },
        });
        if (error) throw error;
        setAiState("success");
        toast.success("Identity provisioned. Welcome to Nexus.");
        setTimeout(() => navigate("/me"), 800);
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        setAiState("success");
        setTimeout(() => navigate("/me"), 600);
      }
    } catch (err) {
      setAiState("error");
      toast.error(err instanceof Error ? err.message : "Authentication failed");
      setTimeout(() => setAiState("idle"), 2200);
    } finally {
      setBusy(false);
    }
  }

  async function google() {
    setBusy(true);
    setAiState("processing");
    const r = await supabase.auth.signInWithOAuth({ provider: "google", options: { redirectTo: `${window.location.origin}/me` } });
    if (r.error) {
      setAiState("error");
      toast.error(r.error.message);
      setBusy(false);
      setTimeout(() => setAiState("idle"), 1500);
    }
  }

  const meta = stateMeta[aiState];

  return (
    <div className="min-h-screen bg-background text-foreground overflow-hidden relative">
      {/* Ambient */}
      <div className="absolute inset-0 pointer-events-none">
        <div className="absolute inset-0 opacity-[0.06] [background-image:linear-gradient(to_right,oklch(0.7_0.18_280)_1px,transparent_1px),linear-gradient(to_bottom,oklch(0.7_0.18_280)_1px,transparent_1px)] [background-size:56px_56px]" />
        <div className="absolute -top-40 -left-40 h-[520px] w-[520px] rounded-full bg-[oklch(0.55_0.22_280/0.22)] blur-[140px]" />
        <div className="absolute -bottom-40 -right-40 h-[600px] w-[600px] rounded-full bg-[oklch(0.6_0.2_300/0.18)] blur-[160px]" />
      </div>

      {/* Top bar */}
      <header className="relative z-10 h-14 px-6 flex items-center justify-between border-b border-border/40 backdrop-blur-xl bg-background/30">
        <Link to="/" className="flex items-center gap-2.5">
          <div className="h-9 w-9 rounded-lg bg-[image:var(--gradient-primary)] grid place-items-center glow-primary">
            <Zap className="h-4 w-4 text-primary-foreground" strokeWidth={2.5} />
          </div>
          <div className="flex flex-col leading-tight">
            <span className="text-[8px] uppercase tracking-[0.28em] text-muted-foreground">Software Vala</span>
            <span className="font-display text-sm font-bold tracking-tight">NEXUS<span className="text-primary"> OS</span></span>
          </div>
        </Link>
        <div className="flex items-center gap-4 text-[10px] uppercase tracking-widest text-muted-foreground">
          <span className="flex items-center gap-1.5"><CircleDot className="h-3 w-3 text-emerald-400 animate-pulse" /> All systems operational</span>
          <span className="hidden md:flex items-center gap-1.5"><ShieldCheck className="h-3 w-3 text-primary" /> Enterprise grade</span>
          <span className="hidden lg:flex items-center gap-1.5"><Globe2 className="h-3 w-3" /> 47 regions</span>
        </div>
      </header>

      <main className="relative z-10 grid grid-cols-1 lg:grid-cols-[1fr_minmax(420px,500px)_1fr] gap-5 px-5 py-5">
        {/* LEFT — Ecosystem opportunities */}
        <aside className="hidden lg:flex flex-col gap-4">
          <div className="panel rounded-2xl p-5 bg-[image:linear-gradient(135deg,oklch(0.3_0.15_280/0.4),oklch(0.2_0.1_300/0.3))] border-primary/30">
            <div className="text-[10px] uppercase tracking-[0.28em] text-primary mb-2">Global Ecosystem</div>
            <h2 className="font-display text-2xl font-bold leading-tight">
              Join Software Vala<br />
              <span className="bg-[image:var(--gradient-primary)] bg-clip-text text-transparent">Nexus OS</span>
            </h2>
            <p className="text-xs text-muted-foreground mt-2">Opportunities for everyone, everywhere.</p>
          </div>

          <div className="panel rounded-2xl p-4 relative">
            <div className="flex items-center justify-between mb-3">
              <span className="text-[10px] uppercase tracking-widest text-muted-foreground">Opportunity stream</span>
              <div className="flex items-center gap-1">
                <button onClick={() => setOppIndex((i) => (i - 1 + opportunities.length) % opportunities.length)} className="h-6 w-6 rounded-md border border-border hover:border-primary/60 grid place-items-center">
                  <ChevronLeft className="h-3 w-3" />
                </button>
                <button onClick={() => setOppIndex((i) => (i + 1) % opportunities.length)} className="h-6 w-6 rounded-md border border-border hover:border-primary/60 grid place-items-center">
                  <ChevronRight className="h-3 w-3" />
                </button>
              </div>
            </div>

            <div className="space-y-2">
              {opportunities.map((o, i) => {
                const active = i === oppIndex;
                return (
                  <div key={o.title} className={`p-3 rounded-xl border transition-all flex items-start gap-3 ${active ? "border-primary/60 bg-primary/10 scale-[1.01]" : "border-border bg-background/40"}`}>
                    <div className={`h-9 w-9 rounded-lg grid place-items-center shrink-0 ${active ? "bg-primary/20 text-primary" : "bg-background/60 text-muted-foreground"}`}>
                      <o.icon className="h-4 w-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-semibold">{o.title}</span>
                        {active && <span className="text-[9px] uppercase tracking-widest text-emerald-400">Hiring</span>}
                      </div>
                      <ul className="mt-1 space-y-0.5">
                        {o.lines.map((l) => (
                          <li key={l} className="text-[10px] text-muted-foreground flex items-center gap-1.5">
                            <span className="h-1 w-1 rounded-full bg-primary/60" /> {l}
                          </li>
                        ))}
                      </ul>
                    </div>
                    {active && (
                      <button className="h-7 px-3 rounded-md bg-[image:var(--gradient-primary)] text-primary-foreground text-[10px] font-semibold uppercase tracking-widest shrink-0">
                        Apply
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          <div className="panel rounded-2xl p-4">
            <div className="flex items-center justify-between mb-3">
              <span className="text-[10px] uppercase tracking-widest text-muted-foreground">Live platform metrics</span>
              <Activity className="h-3 w-3 text-emerald-400 animate-pulse" />
            </div>
            <div className="grid grid-cols-4 gap-2 mb-3">
              {[
                { v: "150+", l: "Modules" },
                { v: "50+",  l: "Roles" },
                { v: "1K+",  l: "Pages" },
                { v: "100+", l: "Countries" },
              ].map((s) => (
                <div key={s.l} className="text-center p-2 rounded-lg border border-border bg-background/40">
                  <div className="font-display text-base font-bold text-primary">{s.v}</div>
                  <div className="text-[9px] text-muted-foreground uppercase tracking-widest">{s.l}</div>
                </div>
              ))}
            </div>
            <div className="space-y-2">
              {[
                { l: "Active sessions", v: "184,392", bar: 78 },
                { l: "Auth latency",    v: "42 ms",   bar: 22 },
              ].map((m) => (
                <div key={m.l}>
                  <div className="flex justify-between text-[10px] mb-1">
                    <span className="text-muted-foreground">{m.l}</span>
                    <span className="text-mono">{m.v}</span>
                  </div>
                  <div className="h-1 rounded-full bg-border/50 overflow-hidden">
                    <div className="h-full bg-[image:var(--gradient-primary)] rounded-full" style={{ width: `${m.bar}%` }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </aside>

        {/* CENTER — Auth gateway */}
        <section className="flex items-start justify-center">
          <div className="w-full panel rounded-2xl p-6 relative overflow-hidden backdrop-blur-2xl">
            <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-primary/60 to-transparent" />

            <div className="text-center mb-5">
              <div className="inline-flex items-center gap-2 px-3 h-6 rounded-full border border-primary/40 bg-primary/10 text-[9px] uppercase tracking-[0.24em] text-primary">
                <ShieldCheck className="h-3 w-3" /> Secure Gateway
              </div>
              <h1 className="font-display text-2xl font-bold mt-3">
                {mode === "signin" ? <>Welcome Back, <span className="text-primary">Boss!</span> 👋</> : <>Provision your <span className="text-primary">identity</span></>}
              </h1>
              <p className="text-xs text-muted-foreground mt-1">
                {mode === "signin" ? "Sign in to continue your journey with Nexus OS" : "One email, one identity, infinite reach"}
              </p>
            </div>

            {/* Auth method tabs */}
            <div className="grid grid-cols-5 gap-1 mb-4 border-b border-border">
              {([
                ["email", "Email"], ["username", "Username"], ["mobile", "Mobile"], ["otp", "OTP"], ["qr", "QR"],
              ] as const).map(([k, label]) => (
                <button key={k} type="button" onClick={() => setTab(k)}
                  className={`h-9 text-[11px] font-semibold uppercase tracking-wider transition-colors border-b-2 -mb-px ${
                    tab === k ? "text-primary border-primary" : "text-muted-foreground border-transparent hover:text-foreground"
                  }`}>
                  {label}
                </button>
              ))}
            </div>

            <form onSubmit={submit} className="space-y-2.5">
              {mode === "signup" && (
                <Field icon={UserIcon} value={name} onChange={setName} placeholder="Full name" />
              )}
              {tab === "mobile" || tab === "otp" ? (
                <Field icon={Phone} value={phone} onChange={setPhone} placeholder="+91 98765 43210" type="tel" />
              ) : tab === "username" ? (
                <Field icon={UserIcon} value={email} onChange={setEmail} placeholder="username" onFocus={() => setAiState("email")} onBlur={() => aiState === "email" && setAiState("idle")} />
              ) : tab === "qr" ? (
                <div className="h-44 rounded-xl border border-border bg-background/40 grid place-items-center">
                  <div className="text-center">
                    <QrCode className="h-12 w-12 mx-auto text-primary mb-2" />
                    <p className="text-xs text-muted-foreground">Scan with Nexus mobile app</p>
                  </div>
                </div>
              ) : (
                <Field icon={Mail} value={email} onChange={setEmail} placeholder="boss@softwarevala.com" type="email"
                  onFocus={() => setAiState("email")} onBlur={() => aiState === "email" && setAiState("idle")} />
              )}

              {tab !== "otp" && tab !== "qr" && (
                <div className="flex items-center gap-2 h-11 rounded-lg border border-border bg-background/40 px-3 focus-within:border-primary/60 transition-colors">
                  <Lock className="h-3.5 w-3.5 text-muted-foreground" />
                  <input
                    required={tab === "email" || tab === "username"} type={showPwd ? "text" : "password"} minLength={6} value={password}
                    onChange={(e) => setPassword(e.target.value)} placeholder="Enter your password"
                    onFocus={() => setAiState(showPwd ? "peek" : "password")}
                    onBlur={() => (aiState === "password" || aiState === "peek") && setAiState("idle")}
                    className="flex-1 bg-transparent text-sm focus:outline-none"
                  />
                  <button type="button" onClick={() => setShowPwd((s) => !s)} className="text-muted-foreground hover:text-foreground">
                    {showPwd ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                  </button>
                </div>
              )}

              {tab === "otp" && (
                <button type="button" className="w-full h-11 rounded-lg border border-primary/40 bg-primary/10 text-primary text-sm font-semibold flex items-center justify-center gap-2">
                  <KeyRound className="h-4 w-4" /> Send OTP
                </button>
              )}

              <div className="flex items-center justify-between text-[11px] pt-1">
                <label className="flex items-center gap-2 cursor-pointer text-muted-foreground hover:text-foreground">
                  <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} className="h-3.5 w-3.5 rounded accent-primary" />
                  Remember me
                </label>
                <button type="button" onClick={() => setAiState("recovery")} className="text-primary font-medium hover:underline">
                  Forgot Password?
                </button>
              </div>

              <button disabled={busy} type="submit"
                className="w-full h-12 mt-2 rounded-lg bg-[image:var(--gradient-primary)] text-primary-foreground font-semibold text-sm hover:opacity-90 glow-primary disabled:opacity-60 flex items-center justify-center gap-3 group">
                {busy ? "Authenticating…" : (
                  <>
                    {mode === "signin" ? "Login Now" : "Create Account"}
                    <span className="h-7 w-7 rounded-full bg-primary-foreground/20 grid place-items-center group-hover:translate-x-0.5 transition-transform">
                      <ArrowRight className="h-3.5 w-3.5" />
                    </span>
                  </>
                )}
              </button>
            </form>

            <div className="my-4 flex items-center gap-3 text-[10px] uppercase tracking-widest text-muted-foreground">
              <div className="flex-1 h-px bg-border" /> Or continue with <div className="flex-1 h-px bg-border" />
            </div>

            <div className="grid grid-cols-3 gap-2">
              <SocialBtn onClick={google} disabled={busy}>
                <svg className="h-4 w-4" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.9 29.3 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.9 1.1 8 3l5.7-5.7C34.6 6.1 29.6 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.2-.1-2.3-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.6 16.1 18.9 13 24 13c3.1 0 5.9 1.1 8 3l5.7-5.7C34.6 7.1 29.6 5 24 5 16.3 5 9.7 9.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.5 0 10.5-2.1 14.3-5.5l-6.6-5.4C29.5 34.7 26.9 36 24 36c-5.3 0-9.7-3.1-11.3-7.5l-6.5 5C9.5 39.8 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.4-2.5 4.4-4.7 5.7l6.6 5.4C41.5 35.4 44 30.1 44 24c0-1.2-.1-2.3-.4-3.5z"/></svg>
                Google
              </SocialBtn>
              <SocialBtn disabled>
                <svg className="h-4 w-4" viewBox="0 0 24 24"><path fill="#F25022" d="M1 1h10v10H1z"/><path fill="#7FBA00" d="M13 1h10v10H13z"/><path fill="#00A4EF" d="M1 13h10v10H1z"/><path fill="#FFB900" d="M13 13h10v10H13z"/></svg>
                Microsoft
              </SocialBtn>
              <SocialBtn disabled>
                <svg className="h-4 w-4" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0C5.4 0 0 5.4 0 12c0 5.3 3.4 9.8 8.2 11.4.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.5-1.4-1.3-1.8-1.3-1.8-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1.1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.8-1.6-2.7-.3-5.5-1.3-5.5-6 0-1.3.5-2.4 1.2-3.2-.1-.3-.5-1.6.1-3.3 0 0 1-.3 3.3 1.2 1-.3 2-.4 3-.4s2 .1 3 .4c2.3-1.5 3.3-1.2 3.3-1.2.7 1.7.2 3 .1 3.3.8.8 1.2 1.9 1.2 3.2 0 4.7-2.8 5.7-5.5 6 .4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6C20.6 21.8 24 17.3 24 12c0-6.6-5.4-12-12-12z"/></svg>
                GitHub
              </SocialBtn>
            </div>

            <div className="mt-5 p-3 rounded-lg border border-emerald-500/30 bg-emerald-500/5 flex items-center gap-3">
              <ShieldCheck className="h-5 w-5 text-emerald-400 shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="text-[11px] font-semibold">Your data is protected with Enterprise Grade Security</div>
                <div className="flex items-center gap-3 text-[9px] text-muted-foreground mt-0.5">
                  <span>✓ Encrypted</span><span>✓ Argon2id</span><span>✓ JWT</span><span>✓ 2FA Ready</span>
                </div>
              </div>
            </div>

            <p className="mt-4 text-center text-[11px] text-muted-foreground">
              {mode === "signin" ? "Don't have an account? " : "Already have an account? "}
              <button onClick={() => setMode(mode === "signin" ? "signup" : "signin")} className="text-primary font-semibold hover:underline">
                {mode === "signin" ? "Create Account" : "Sign in"}
              </button>
            </p>
          </div>
        </section>

        {/* RIGHT — Live AI Assistant */}
        <aside className="hidden lg:flex flex-col gap-4">
          <div className="panel rounded-2xl p-5 relative overflow-hidden">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <div className="h-8 w-8 rounded-lg bg-primary/20 border border-primary/40 grid place-items-center">
                  <Zap className="h-4 w-4 text-primary" />
                </div>
                <div>
                  <div className="text-[10px] uppercase tracking-[0.28em] text-muted-foreground">Nexus</div>
                  <div className="text-sm font-bold font-display">AI Assistant</div>
                </div>
              </div>
              <span className="flex items-center gap-1.5 text-[10px] text-emerald-400">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" /> Listening…
              </span>
            </div>

            {/* AI dialog bubble */}
            <div className="p-3 rounded-xl border border-primary/30 bg-primary/5 mb-3">
              <div className={`text-xs font-semibold ${meta.tone}`}>{meta.title}</div>
              <p className="text-[11px] text-foreground/80 mt-1 leading-relaxed">{meta.msg}</p>
              <div className="mt-2 flex items-center gap-0.5 h-3">
                {[...Array(20)].map((_, i) => (
                  <span key={i} className="w-0.5 bg-primary rounded-full animate-pulse"
                    style={{ height: `${30 + Math.sin(i + aiState.length) * 50 + 20}%`, animationDelay: `${i * 80}ms` }} />
                ))}
              </div>
            </div>

            {/* The live AI girl photo */}
            <div className="relative h-72 rounded-xl overflow-hidden bg-[image:linear-gradient(180deg,oklch(0.25_0.1_280/0.4),oklch(0.18_0.08_300/0.3))] border border-border">
              <div className="absolute inset-0 [background:radial-gradient(circle_at_50%_30%,oklch(0.7_0.18_280/0.25),transparent_70%)]" />
              <img
                src={meta.img}
                alt="Nexus AI Assistant"
                className="absolute inset-0 w-full h-full object-contain object-bottom transition-all duration-500 ease-out animate-fade-in"
                key={aiState}
                loading="lazy"
                width={512}
                height={640}
              />
              {aiState === "processing" && (
                <div className="absolute inset-0 [background:repeating-linear-gradient(0deg,transparent,transparent_4px,oklch(0.7_0.18_280/0.08)_4px,oklch(0.7_0.18_280/0.08)_5px)] animate-pulse" />
              )}
              <div className="absolute top-2 right-2 flex items-center gap-1 px-2 h-6 rounded-full bg-background/70 backdrop-blur text-[9px] uppercase tracking-widest border border-border">
                <span className={`h-1.5 w-1.5 rounded-full ${aiState === "success" ? "bg-emerald-400" : aiState === "error" ? "bg-destructive" : "bg-primary"} animate-pulse`} />
                {aiState}
              </div>
            </div>

            {/* Controls */}
            <div className="mt-3 grid grid-cols-2 gap-2">
              <div className="p-2 rounded-lg border border-border bg-background/40 flex items-center gap-2">
                <Languages className="h-3.5 w-3.5 text-primary" />
                <div className="flex-1 min-w-0">
                  <div className="text-[9px] uppercase tracking-widest text-muted-foreground">Language</div>
                  <div className="text-[11px] font-semibold truncate">English (US)</div>
                </div>
              </div>
              <button onClick={() => setVoiceOn((v) => !v)} className={`p-2 rounded-lg border flex items-center gap-2 transition-colors ${voiceOn ? "border-primary bg-primary/10" : "border-border bg-background/40"}`}>
                <Mic className={`h-3.5 w-3.5 ${voiceOn ? "text-primary" : "text-muted-foreground"}`} />
                <div className="flex-1 min-w-0 text-left">
                  <div className="text-[9px] uppercase tracking-widest text-muted-foreground">Voice</div>
                  <div className="text-[11px] font-semibold">{voiceOn ? "Female · Neural" : "Tap to enable"}</div>
                </div>
              </button>
            </div>

            <button className="mt-2 w-full h-9 rounded-lg border border-border bg-background/40 hover:border-primary/60 text-[11px] font-medium flex items-center justify-center gap-2 transition-colors">
              <Headphones className="h-3.5 w-3.5" /> Contact human support
            </button>
          </div>

          <div className="panel rounded-2xl p-4">
            <div className="text-[10px] uppercase tracking-widest text-muted-foreground mb-3">AI Awareness</div>
            <div className="space-y-2 text-[11px]">
              <Awareness label="Presence detected" value="Active" />
              <Awareness label="Device fingerprint" value="Trusted" />
              <Awareness label="Threat model" value="Nominal" />
              <Awareness label="Geo signal" value="India · Mumbai" />
            </div>
          </div>
        </aside>
      </main>

      {/* Footer status bar */}
      <footer className="relative z-10 mx-5 mb-5 panel rounded-2xl p-3 grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 text-[11px]">
        <Stat dot="emerald" label="System Status" value="All Systems Operational" />
        <Stat dot="emerald" label="Server Health" value="100%" />
        <Stat dot="emerald" label="Security" value="Secure" />
        <Stat dot="primary" label="Last Login" value="12 May, 10:30 AM" />
        <Stat dot="primary" label="Active Sessions" value="3 Active" />
        <Stat dot="primary" label="Your IP" value="103.21.244.xxx" />
      </footer>
      <Toaster />
    </div>
  );
}

function Field({
  icon: Icon, value, onChange, placeholder, type = "text", onFocus, onBlur,
}: {
  icon: React.ComponentType<{ className?: string }>; value: string;
  onChange: (v: string) => void; placeholder?: string; type?: string;
  onFocus?: () => void; onBlur?: () => void;
}) {
  return (
    <div className="flex items-center gap-2 h-11 rounded-lg border border-border bg-background/40 px-3 focus-within:border-primary/60 transition-colors">
      <Icon className="h-3.5 w-3.5 text-muted-foreground" />
      <input
        type={type} value={value}
        onChange={(e) => onChange(e.target.value)} placeholder={placeholder}
        onFocus={onFocus} onBlur={onBlur}
        className="flex-1 bg-transparent text-sm focus:outline-none"
      />
    </div>
  );
}

function SocialBtn({ children, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button type="button" {...props}
      className="h-10 rounded-lg border border-border bg-background/40 hover:border-primary/60 flex items-center justify-center gap-1.5 text-[11px] font-medium disabled:opacity-50 transition-colors">
      {children}
    </button>
  );
}

function Awareness({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-semibold text-emerald-400 flex items-center gap-1">
        <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" /> {value}
      </span>
    </div>
  );
}

function Stat({ dot, label, value }: { dot: "emerald" | "primary"; label: string; value: string }) {
  return (
    <div className="flex items-center gap-2.5">
      <span className={`h-2 w-2 rounded-full animate-pulse ${dot === "emerald" ? "bg-emerald-400" : "bg-primary"}`} />
      <div className="min-w-0">
        <div className="text-[9px] uppercase tracking-widest text-muted-foreground">{label}</div>
        <div className="font-semibold truncate">{value}</div>
      </div>
    </div>
  );
}

export default AuthPage;
