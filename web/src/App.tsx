import {
  ArrowDownCircle,
  ArrowUpCircle,
  Banknote,
  BarChart3,
  CalendarDays,
  CheckCircle2,
  CircleDollarSign,
  Cloud,
  Download,
  HardDrive,
  Home,
  LogIn,
  LogOut,
  Mail,
  Plus,
  RefreshCcw,
  Search,
  Settings,
  SlidersHorizontal,
  Trash2,
  Upload,
  Users,
  X
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import type { CSSProperties, FormEvent } from "react";
import type { Session, User } from "@supabase/supabase-js";
import { categoryColor, categoryName, categoryTextColor, expenseCategories, incomeCategories } from "./domain/categories";
import { currencyOptions, formatMoney } from "./domain/currency";
import {
  categoryBreakdown,
  currentMonthKey,
  dashboardTotals,
  involvesMember,
  memberExpenseTotals,
  monthlyBudget,
  normalizeAmount,
  settlementSuggestions,
  transactionsForMonth
} from "./domain/budgetMath";
import { defaultBudgetSettings } from "./domain/defaults";
import type { AppState, BudgetInvite, BudgetMember, BudgetSettings, BudgetTransaction, TransactionType } from "./domain/types";
import {
  acceptCloudInvite,
  createCloudInvite,
  createCloudSharedBudget,
  deleteCloudTransaction,
  fetchCloudState,
  fetchPendingInvites,
  signInWithEmail,
  signOut,
  signUpWithEmail,
  upsertCloudMember,
  upsertCloudSettings,
  upsertCloudTransaction
} from "./data/cloudRepository";
import { exportState, importState, loadState, resetState, saveState } from "./data/storage";
import { supabase, supabaseConfigStatus } from "./data/supabaseClient";

type Tab = "dashboard" | "transactions" | "budget" | "settings";
type SyncMode = "cloud" | "local";

type TransactionFormState = {
  type: TransactionType;
  title: string;
  amount: string;
  category: string;
  paymentMethod: "cash" | "card" | "paypal";
  createdByMemberId: string;
  date: string;
  splitWithHousehold: boolean;
};

const todayInputValue = () => new Date().toISOString().slice(0, 10);
const makeId = () => crypto.randomUUID();
const CLOUD_AUTO_REFRESH_INTERVAL_MS = 6000;

function memberInitials(name: string): string {
  const parts = name
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (parts.length >= 2) {
    return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  }

  return parts[0]?.[0]?.toUpperCase() ?? "?";
}

function App() {
  const [state, setState] = useState<AppState>(() => loadState());
  const [syncMode, setSyncMode] = useState<SyncMode>(supabaseConfigStatus === "configured" ? "cloud" : "local");
  const [session, setSession] = useState<Session | null>(null);
  const [authLoading, setAuthLoading] = useState(supabaseConfigStatus === "configured");
  const [isCloudLoading, setIsCloudLoading] = useState(false);
  const [cloudMessage, setCloudMessage] = useState(
    supabaseConfigStatus === "configured" ? "Sign in to sync with Supabase." : "Desktop local mode."
  );
  const [cloudError, setCloudError] = useState("");
  const [pendingInvites, setPendingInvites] = useState<BudgetInvite[]>([]);
  const [activeTab, setActiveTab] = useState<Tab>("dashboard");
  const [selectedMonth, setSelectedMonth] = useState(currentMonthKey());
  const [selectedMemberId, setSelectedMemberId] = useState<string>("all");
  const [isAddingTransaction, setIsAddingTransaction] = useState(false);
  const [transactionSearch, setTransactionSearch] = useState("");
  const [importText, setImportText] = useState("");
  const [importError, setImportError] = useState("");
  const cloudRefreshInFlight = useRef(false);
  const addTransactionButtonRef = useRef<HTMLButtonElement | null>(null);

  const canUseCloud = syncMode === "cloud" && !!session?.user && !!supabase;
  const currentBudget =
    state.budgets.find((budget) => budget.id === state.currentBudgetId) ??
    state.budgets[0] ?? {
      id: state.currentUserId,
      ownerUserId: state.currentUserId,
      name: "My Budget",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
  const settings = state.settingsByBudgetId[currentBudget.id] ?? defaultBudgetSettings(currentBudget.id);
  const budgetMembers = state.members.filter((member) => member.budgetId === currentBudget.id);
  const budgetTransactions = state.transactions.filter((transaction) => transaction.budgetId === currentBudget.id);
  const budgetSettlements = state.settlements.filter((settlement) => settlement.budgetId === currentBudget.id);
  const monthTransactions = useMemo(
    () => transactionsForMonth(budgetTransactions, selectedMonth),
    [budgetTransactions, selectedMonth]
  );
  const memberFilter = selectedMemberId === "all" ? undefined : selectedMemberId;
  const displayedTransactions = monthTransactions.filter((transaction) =>
    memberFilter ? involvesMember(transaction, memberFilter) : true
  );
  const totals = dashboardTotals(monthTransactions, monthlyBudget(settings), memberFilter);
  const categoryTotals = categoryBreakdown(monthTransactions, memberFilter);
  const settlements = settlementSuggestions(budgetTransactions, budgetSettlements, budgetMembers);
  const activeTabTitle: Record<Tab, string> = {
    dashboard: "Dashboard",
    transactions: "Transactions",
    budget: "Budget",
    settings: "Settings"
  };

  useEffect(() => {
    if (!supabase) {
      setAuthLoading(false);
      return;
    }

    let isMounted = true;
    supabase.auth.getSession().then(({ data, error }) => {
      if (!isMounted) {
        return;
      }
      if (error) {
        setCloudError(error.message);
      }
      setSession(data.session);
      setAuthLoading(false);
    });

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (!nextSession) {
        setPendingInvites([]);
        setCloudMessage("Signed out. Desktop local data is still available.");
      }
    });

    return () => {
      isMounted = false;
      data.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    saveState(state);
  }, [state]);

  useEffect(() => {
    if (selectedMemberId !== "all" && !budgetMembers.some((member) => member.id === selectedMemberId)) {
      setSelectedMemberId("all");
    }
  }, [budgetMembers, selectedMemberId]);

  useEffect(() => {
    if (syncMode !== "cloud" || !session?.user) {
      return;
    }
    void reloadCloudState();
  }, [session?.user.id, syncMode]);

  useEffect(() => {
    if (!canUseCloud) {
      return;
    }

    const refreshInBackground = () => {
      if (document.visibilityState !== "visible") {
        return;
      }
      void reloadCloudState(state.currentBudgetId, { background: true });
    };

    const intervalId = window.setInterval(refreshInBackground, CLOUD_AUTO_REFRESH_INTERVAL_MS);
    window.addEventListener("focus", refreshInBackground);
    document.addEventListener("visibilitychange", refreshInBackground);

    return () => {
      window.clearInterval(intervalId);
      window.removeEventListener("focus", refreshInBackground);
      document.removeEventListener("visibilitychange", refreshInBackground);
    };
  }, [canUseCloud, session?.user.id, state.currentBudgetId]);

  async function reloadCloudState(preferredBudgetId = state.currentBudgetId, options: { background?: boolean } = {}) {
    if (!session?.user) {
      return;
    }

    if (cloudRefreshInFlight.current) {
      return;
    }

    cloudRefreshInFlight.current = true;
    if (!options.background) {
      setIsCloudLoading(true);
    }
    setCloudError("");
    try {
      const nextState = await fetchCloudState(session.user, preferredBudgetId);
      const invites = await fetchPendingInvites(session.user.email ?? "");
      setState(nextState);
      setPendingInvites(invites);
      setCloudMessage("Synced just now");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Cloud sync failed.";
      setCloudError(message);
      setCloudMessage("Needs attention");
    } finally {
      cloudRefreshInFlight.current = false;
      if (!options.background) {
        setIsCloudLoading(false);
      }
    }
  }

  async function runCloudMutation(action: () => Promise<void>, successMessage = "Synced just now") {
    if (!canUseCloud) {
      return;
    }

    setCloudError("");
    setCloudMessage("Syncing now");
    try {
      await action();
      setCloudMessage(successMessage);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Cloud write failed.";
      setCloudError(message);
      setCloudMessage("Needs attention");
    }
  }

  function updateSettings(nextSettings: BudgetSettings) {
    setState((current) => ({
      ...current,
      settingsByBudgetId: {
        ...current.settingsByBudgetId,
        [nextSettings.budgetId]: nextSettings
      }
    }));

    void runCloudMutation(() => upsertCloudSettings(nextSettings, state.currentUserId));
  }

  function addTransaction(form: TransactionFormState) {
    const amount = normalizeAmount(Number(form.amount));
    if (amount <= 0 || !form.title.trim()) {
      return;
    }

    const splitWithHousehold = form.type === "expense" && form.splitWithHousehold && budgetMembers.length > 1;
    const baseShare = splitWithHousehold ? Math.floor((amount * 100) / budgetMembers.length) / 100 : 0;
    const splits = splitWithHousehold
      ? budgetMembers.map((member, index) => {
          const isLast = index === budgetMembers.length - 1;
          const previous = baseShare * (budgetMembers.length - 1);
          return {
            id: makeId(),
            memberId: member.id,
            amount: isLast ? normalizeAmount(amount - previous) : baseShare
          };
        })
      : [];

    const transaction: BudgetTransaction = {
      id: makeId(),
      budgetId: currentBudget.id,
      userId: state.currentUserId,
      title: form.title.trim(),
      amount,
      type: form.type,
      category: form.category,
      paymentMethod: form.paymentMethod,
      createdByMemberId: form.createdByMemberId,
      date: new Date(`${form.date}T12:00:00`).toISOString(),
      createdAt: new Date().toISOString(),
      splits
    };

    setState((current) => ({
      ...current,
      transactions: [transaction, ...current.transactions]
    }));
    void runCloudMutation(() => upsertCloudTransaction(transaction, state.currentUserId));
    setIsAddingTransaction(false);
    window.setTimeout(() => addTransactionButtonRef.current?.focus(), 0);
  }

  function closeTransactionDialog() {
    setIsAddingTransaction(false);
    window.setTimeout(() => addTransactionButtonRef.current?.focus(), 0);
  }

  function deleteTransaction(id: string) {
    const transaction = state.transactions.find((candidate) => candidate.id === id);
    setState((current) => ({
      ...current,
      transactions: current.transactions.filter((transaction) => transaction.id !== id)
    }));

    if (transaction) {
      void runCloudMutation(() => deleteCloudTransaction(transaction.id, transaction.budgetId));
    }
  }

  function addMember(name: string, email: string) {
    if (!name.trim()) {
      return;
    }

    const palette = ["#3B8FE2", "#E2572E", "#1FA37D", "#7B6EE6"];
    const emailValue = email.trim();
    const shouldSendInvite = canUseCloud && !!emailValue;
    const member: BudgetMember = {
      id: makeId(),
      budgetId: currentBudget.id,
      displayName: name.trim(),
      email: emailValue || undefined,
      initials: memberInitials(name),
      color: palette[budgetMembers.length % palette.length],
      role: "member",
      inviteStatus: shouldSendInvite ? "invited" : "active",
      joinedDate: shouldSendInvite ? undefined : new Date().toISOString(),
      createdDate: new Date().toISOString()
    };

    setState((current) => ({
      ...current,
      members: [...current.members, member]
    }));

    void runCloudMutation(
      () => (shouldSendInvite ? createCloudInvite(member, state.currentUserId) : upsertCloudMember(member, state.currentUserId)),
      shouldSendInvite ? "Invite saved" : "Member saved"
    );
  }

  function handleImport() {
    const nextState = importState(importText);
    if (!nextState) {
      setImportError("That file does not match BudgetMate web data.");
      return;
    }
    setImportError("");
    setImportText("");
    setState(nextState);
  }

  async function handleAuthSubmit(mode: "signin" | "signup", email: string, password: string, displayName: string) {
    setAuthLoading(true);
    setCloudError("");
    try {
      const nextSession =
        mode === "signin"
          ? await signInWithEmail(email, password)
          : await signUpWithEmail(email, password, displayName);

      if (nextSession) {
        setSession(nextSession);
        setSyncMode("cloud");
        setCloudMessage("Signed in. Loading cloud data.");
      } else {
        setCloudMessage("Check your email to finish creating the account.");
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : "Authentication failed.";
      setCloudError(message);
    } finally {
      setAuthLoading(false);
    }
  }

  async function handleSignOut() {
    setAuthLoading(true);
    setCloudError("");
    try {
      await signOut();
      setSession(null);
      setSyncMode("local");
      setCloudMessage("Signed out. Desktop local mode is active.");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Sign out failed.";
      setCloudError(message);
    } finally {
      setAuthLoading(false);
    }
  }

  function selectBudget(budgetId: string) {
    setState((current) => ({
      ...current,
      currentBudgetId: budgetId
    }));
  }

  async function createSharedBudget(name: string) {
    if (!session?.user) {
      return;
    }

    setIsCloudLoading(true);
    setCloudError("");
    try {
      const budgetId = await createCloudSharedBudget(name, session.user);
      await reloadCloudState(budgetId);
      setCloudMessage("Shared budget created");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Could not create shared budget.";
      setCloudError(message);
      setCloudMessage("Needs attention");
    } finally {
      setIsCloudLoading(false);
    }
  }

  async function acceptInvite(invite: BudgetInvite) {
    if (!session?.user) {
      return;
    }

    setIsCloudLoading(true);
    setCloudError("");
    try {
      await acceptCloudInvite(invite, session.user.id);
      await reloadCloudState(invite.budgetId);
      setCloudMessage("Invite accepted");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Could not accept invite.";
      setCloudError(message);
      setCloudMessage("Needs attention");
    } finally {
      setIsCloudLoading(false);
    }
  }

  if (authLoading && syncMode === "cloud") {
    return <LoadingScreen message="Checking your BudgetMate session" />;
  }

  if (syncMode === "cloud" && !session && supabase) {
    return (
      <AuthGate
        errorMessage={cloudError}
        statusMessage={cloudMessage}
        onSubmit={handleAuthSubmit}
        onUseLocal={() => {
          setSyncMode("local");
          setCloudError("");
          setCloudMessage("Desktop local mode.");
        }}
      />
    );
  }

  return (
    <div className="app-shell">
      <Sidebar
        activeTab={activeTab}
        onTabChange={setActiveTab}
        syncMode={syncMode}
        statusText={cloudError || cloudMessage}
        userEmail={session?.user.email}
      />
      <main className="workspace">
        <header className="topbar">
          <div className="topbar-title">
            <p className="eyebrow">BudgetMate</p>
            <h1>{activeTabTitle[activeTab]}</h1>
            <span>{currentBudget.name}</span>
          </div>
          <div className="topbar-actions">
            <label className="month-control">
              <CalendarDays size={18} aria-hidden="true" />
              <input
                type="month"
                value={selectedMonth}
                onChange={(event) => setSelectedMonth(event.target.value)}
                aria-label="Selected month"
              />
            </label>
            {state.budgets.length > 1 && (
              <label className="budget-picker">
                <Home size={18} aria-hidden="true" />
                <select value={currentBudget.id} onChange={(event) => selectBudget(event.target.value)} aria-label="Budget">
                  {state.budgets.map((budget) => (
                    <option key={budget.id} value={budget.id}>
                      {budget.name}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {canUseCloud && (
              <button className="secondary-action compact" onClick={() => void reloadCloudState()} disabled={isCloudLoading}>
                <RefreshCcw size={17} aria-hidden="true" />
                Refresh
              </button>
            )}
            {syncMode === "local" && supabase && (
              <button className="secondary-action compact" onClick={() => setSyncMode("cloud")}>
                <Cloud size={17} aria-hidden="true" />
                Cloud
              </button>
            )}
            {canUseCloud && (
              <button className="icon-button" onClick={() => void handleSignOut()} title="Sign out">
                <LogOut size={17} aria-hidden="true" />
              </button>
            )}
            <button
              className="primary-action"
              onClick={() => setIsAddingTransaction(true)}
              ref={addTransactionButtonRef}
              type="button"
            >
              <Plus size={18} aria-hidden="true" />
              Add
            </button>
          </div>
        </header>

        <div className="context-strip">
          <StatusBanner syncMode={syncMode} message={cloudError || cloudMessage} isError={!!cloudError} isLoading={isCloudLoading} />
          {activeTab !== "settings" && (
            <MemberFilter members={budgetMembers} selectedMemberId={selectedMemberId} onSelect={setSelectedMemberId} />
          )}
        </div>

        {activeTab === "dashboard" && (
          <DashboardView
            settings={settings}
            totals={totals}
            categoryTotals={categoryTotals}
            settlements={settlements}
            transactions={displayedTransactions}
          />
        )}

        {activeTab === "transactions" && (
          <TransactionsView
            settings={settings}
            transactions={displayedTransactions}
            members={budgetMembers}
            search={transactionSearch}
            onSearch={setTransactionSearch}
            onDelete={deleteTransaction}
          />
        )}

        {activeTab === "budget" && (
          <BudgetView
            settings={settings}
            totals={totals}
            transactions={monthTransactions}
            members={budgetMembers}
            onSettingsChange={updateSettings}
          />
        )}

        {activeTab === "settings" && (
          <SettingsView
            settings={settings}
            state={state}
            members={budgetMembers}
            importText={importText}
            importError={importError}
            onSettingsChange={updateSettings}
            onAddMember={addMember}
            onImportTextChange={setImportText}
            onImport={handleImport}
            onReset={() => {
              if (window.confirm("Reset all BudgetMate web data on this computer? This cannot be undone.")) {
                setState(resetState());
              }
            }}
            syncMode={syncMode}
            user={session?.user}
            cloudMessage={cloudMessage}
            cloudError={cloudError}
            pendingInvites={pendingInvites}
            onRefresh={() => void reloadCloudState()}
            onSignOut={() => void handleSignOut()}
            onCreateSharedBudget={(name) => void createSharedBudget(name)}
            onAcceptInvite={(invite) => void acceptInvite(invite)}
          />
        )}
      </main>

      {isAddingTransaction && (
          <TransactionDialog
            members={budgetMembers}
            onClose={closeTransactionDialog}
            onSubmit={addTransaction}
          />
      )}
    </div>
  );
}

function LoadingScreen({ message }: { message: string }) {
  return (
    <main className="auth-shell">
      <section className="auth-panel">
        <div className="brand-lockup">
          <div className="brand-mark">BM</div>
          <div>
            <strong>BudgetMate</strong>
            <span>{message}</span>
          </div>
        </div>
        <div className="loading-bar" aria-hidden="true">
          <span />
        </div>
      </section>
    </main>
  );
}

function AuthGate({
  errorMessage,
  statusMessage,
  onSubmit,
  onUseLocal
}: {
  errorMessage: string;
  statusMessage: string;
  onSubmit: (mode: "signin" | "signup", email: string, password: string, displayName: string) => Promise<void>;
  onUseLocal: () => void;
}) {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setIsSubmitting(true);
    try {
      await onSubmit(mode, email, password, displayName);
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-panel">
        <div className="brand-lockup">
          <div className="brand-mark">BM</div>
          <div>
            <strong>BudgetMate</strong>
            <span>Shared household budgeting</span>
          </div>
        </div>

        <div>
          <p className="eyebrow">Cloud sync</p>
          <h1>{mode === "signin" ? "Sign in" : "Create account"}</h1>
        </div>

        <form className="auth-form" onSubmit={handleSubmit}>
          {mode === "signup" && (
            <label className="field-row vertical">
              <span>Name</span>
              <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="Your name" />
            </label>
          )}
          <label className="field-row vertical">
            <span>Email</span>
            <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" />
          </label>
          <label className="field-row vertical">
            <span>Password</span>
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Password"
            />
          </label>
          {errorMessage && <p className="form-error" role="alert">{errorMessage}</p>}
          {!errorMessage && statusMessage && <p className="form-note" role="status" aria-live="polite">{statusMessage}</p>}
          <button className="primary-action full" type="submit" disabled={isSubmitting}>
            <LogIn size={18} aria-hidden="true" />
            {isSubmitting ? "Working" : mode === "signin" ? "Sign in" : "Create account"}
          </button>
        </form>

        <div className="auth-actions">
          <button className="secondary-action" onClick={() => setMode(mode === "signin" ? "signup" : "signin")}>
            <Mail size={17} aria-hidden="true" />
            {mode === "signin" ? "Create account" : "Use sign in"}
          </button>
          <button className="secondary-action quiet" onClick={onUseLocal}>
            <HardDrive size={17} aria-hidden="true" />
            Use this computer
          </button>
        </div>
      </section>
    </main>
  );
}

function StatusBanner({
  syncMode,
  message,
  isError,
  isLoading
}: {
  syncMode: SyncMode;
  message: string;
  isError: boolean;
  isLoading: boolean;
}) {
  return (
    <div
      className={isError ? "status-banner error" : "status-banner"}
      role={isError ? "alert" : "status"}
      aria-live={isError ? "assertive" : "polite"}
    >
      {syncMode === "cloud" ? <Cloud size={17} aria-hidden="true" /> : <HardDrive size={17} aria-hidden="true" />}
      <span>{isLoading ? "Syncing now" : message}</span>
    </div>
  );
}

function Sidebar({
  activeTab,
  onTabChange,
  syncMode,
  statusText,
  userEmail
}: {
  activeTab: Tab;
  onTabChange: (tab: Tab) => void;
  syncMode: SyncMode;
  statusText: string;
  userEmail?: string;
}) {
  const tabs: Array<{ id: Tab; label: string; icon: typeof Home }> = [
    { id: "dashboard", label: "Dashboard", icon: Home },
    { id: "transactions", label: "Transactions", icon: Banknote },
    { id: "budget", label: "Budget", icon: BarChart3 },
    { id: "settings", label: "Settings", icon: Settings }
  ];

  return (
    <aside className="sidebar">
      <div className="brand-lockup">
        <div className="brand-mark">BM</div>
        <div>
          <strong>BudgetMate</strong>
          <span>Household hub</span>
        </div>
      </div>
      <nav aria-label="Primary navigation">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          return (
            <button
              key={tab.id}
              className={activeTab === tab.id ? "nav-item active" : "nav-item"}
              onClick={() => onTabChange(tab.id)}
              aria-current={activeTab === tab.id ? "page" : undefined}
              type="button"
            >
              <Icon size={19} aria-hidden="true" />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </nav>
      <div className="sync-card">
        {syncMode === "cloud" ? <Cloud size={18} aria-hidden="true" /> : <CheckCircle2 size={18} aria-hidden="true" />}
        <div>
          <strong>{syncMode === "cloud" ? "Cloud sync" : "Device data"}</strong>
          <span>{userEmail ?? statusText}</span>
        </div>
      </div>
    </aside>
  );
}

function MemberFilter({
  members,
  selectedMemberId,
  onSelect
}: {
  members: BudgetMember[];
  selectedMemberId: string;
  onSelect: (memberId: string) => void;
}) {
  return (
    <div className="member-strip" aria-label="Member filter">
      <button
        className={selectedMemberId === "all" ? "member-chip active" : "member-chip"}
        onClick={() => onSelect("all")}
        aria-pressed={selectedMemberId === "all"}
        type="button"
      >
        <Users size={16} aria-hidden="true" />
        Everyone
      </button>
      {members.map((member) => (
        <button
          key={member.id}
          className={selectedMemberId === member.id ? "member-chip active" : "member-chip"}
          onClick={() => onSelect(member.id)}
          aria-pressed={selectedMemberId === member.id}
          type="button"
        >
          <MemberBadge member={member} />
          {member.displayName.split(" ")[0]}
        </button>
      ))}
    </div>
  );
}

function DashboardView({
  settings,
  totals,
  categoryTotals,
  settlements,
  transactions
}: {
  settings: BudgetSettings;
  totals: ReturnType<typeof dashboardTotals>;
  categoryTotals: ReturnType<typeof categoryBreakdown>;
  settlements: ReturnType<typeof settlementSuggestions>;
  transactions: BudgetTransaction[];
}) {
  const budgetLimit = monthlyBudget(settings);
  const spentRatio = budgetLimit > 0 ? Math.min(1, Math.max(0, totals.totalExpenses / budgetLimit)) : 0;
  const savingsRate = totals.totalIncome > 0
    ? Math.max(0, ((totals.totalIncome - totals.totalExpenses) / totals.totalIncome) * 100)
    : 0;
  const topCategory = categoryTotals[0];
  const insightText = topCategory
    ? `${categoryName(topCategory.category)} is your largest expense this month.`
    : "Add expenses to unlock category insights.";

  return (
    <section className="dashboard-grid">
      <div className="balance-panel">
        <p className="eyebrow">Total balance</p>
        <strong>{formatMoney(totals.currentBalance, settings.currencyCode)}</strong>
        <div className="pacing">
          <div>
            <span>Monthly budget</span>
            <b>{formatMoney(budgetLimit, settings.currencyCode)}</b>
          </div>
          <div className="progress-track" aria-hidden="true">
            <span style={{ width: `${spentRatio * 100}%` }} />
          </div>
        </div>
      </div>

      <SummaryTile label="Income" amount={totals.totalIncome} currencyCode={settings.currencyCode} tone="income" />
      <SummaryTile label="Expenses" amount={totals.totalExpenses} currencyCode={settings.currencyCode} tone="expense" />
      <SummaryTile
        label="Savings rate"
        amount={savingsRate}
        currencyCode={settings.currencyCode}
        tone="warning"
        format="percent"
      />

      <section className="panel category-panel">
        <div className="panel-heading">
          <h2>Expense breakdown</h2>
          <span>{categoryTotals.length} active</span>
        </div>
        <ExpenseBreakdownChart items={categoryTotals.slice(0, 5)} total={totals.totalExpenses} />
      </section>

      <section className="panel settlement-panel">
        <div className="panel-heading">
          <h2>Top spending categories</h2>
          <span>{formatMoney(totals.totalExpenses, settings.currencyCode)}</span>
        </div>
        <TopSpendingChart items={categoryTotals.slice(0, 6)} currencyCode={settings.currencyCode} />
      </section>

      <section className="panel recent-panel">
        <div className="panel-heading">
          <h2>Recent activity</h2>
          <span>{transactions.length} rows</span>
        </div>
        <TransactionList transactions={transactions.slice(0, 5)} settings={settings} />
      </section>

      <section className="panel settle-panel">
        <div className="panel-heading">
          <h2>Settle up</h2>
          <span>{settlements.length ? "Open" : "Clear"}</span>
        </div>
        <div className="settlement-list">
          {settlements.length === 0 ? (
            <div className="empty-state">No open household balances.</div>
          ) : (
            settlements.slice(0, 4).map((settlement) => (
              <div key={settlement.id} className="settlement-row">
                <div className="avatar-pair">
                  <MemberBadge member={settlement.from} />
                  <MemberBadge member={settlement.to} />
                </div>
                <div>
                  <strong>
                    {settlement.from.displayName.split(" ")[0]} pays {settlement.to.displayName.split(" ")[0]}
                  </strong>
                  <span>{formatMoney(settlement.amount, settings.currencyCode)}</span>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      <section className="panel insight-panel">
        <div className="panel-heading">
          <h2>Spending insights</h2>
          <span>This month</span>
        </div>
        <div className="insight-card">
          <strong>{insightText}</strong>
          <span>
            {budgetLimit > 0
              ? `${Math.round(spentRatio * 100)}% of your monthly budget is used.`
              : "Set a monthly budget to track your pacing."}
          </span>
        </div>
      </section>
    </section>
  );
}

function SummaryTile({
  label,
  amount,
  currencyCode,
  tone,
  format = "money"
}: {
  label: string;
  amount: number;
  currencyCode: string;
  tone: "income" | "expense" | "warning";
  format?: "money" | "percent";
}) {
  const Icon = tone === "income" ? ArrowUpCircle : tone === "expense" ? ArrowDownCircle : CircleDollarSign;
  const displayValue = format === "percent" ? `${amount.toFixed(2)}%` : formatMoney(amount, currencyCode);
  return (
    <section className={`summary-tile ${tone}`} aria-label={`${label}: ${displayValue}`}>
      <Icon size={20} aria-hidden="true" />
      <span>{label}</span>
      <strong>{displayValue}</strong>
    </section>
  );
}

function ExpenseBreakdownChart({
  items,
  total
}: {
  items: ReturnType<typeof categoryBreakdown>;
  total: number;
}) {
  if (items.length === 0 || total <= 0) {
    return <div className="empty-state">No expenses in this view.</div>;
  }

  return (
    <div className="breakdown-chart" aria-label="Expense breakdown">
      {items.map((item, index) => {
        const percentage = Math.round((item.amount / total) * 100);
        const heightPercentage = Math.max(8, percentage);
        const style = {
          "--category-color": categoryColor(item.category),
          "--category-ink": categoryTextColor(item.category),
          height: `${Math.min(100, heightPercentage + 18)}%`
        } as CSSProperties;
        return (
          <div
            key={item.category}
            className={`breakdown-bar bar-${index % 5}`}
            style={style}
          >
            <strong>{percentage}%</strong>
            <span>{categoryName(item.category)}</span>
          </div>
        );
      })}
    </div>
  );
}

function TopSpendingChart({
  items,
  currencyCode
}: {
  items: ReturnType<typeof categoryBreakdown>;
  currencyCode: string;
}) {
  const maxAmount = Math.max(...items.map((item) => item.amount), 0);

  if (items.length === 0 || maxAmount <= 0) {
    return <div className="empty-state">No category spending yet.</div>;
  }

  return (
    <div className="top-spending-chart" aria-label="Top spending categories">
      {items.map((item) => (
        <div
          key={item.category}
          className="spending-bar-row"
          style={{ "--category-color": categoryColor(item.category) } as CSSProperties}
        >
          <span>{categoryName(item.category)}</span>
          <div className="spending-track">
            <b style={{ width: `${Math.max(8, (item.amount / maxAmount) * 100)}%` }} />
          </div>
          <strong>{formatMoney(item.amount, currencyCode)}</strong>
        </div>
      ))}
    </div>
  );
}

function TransactionsView({
  settings,
  transactions,
  members,
  search,
  onSearch,
  onDelete
}: {
  settings: BudgetSettings;
  transactions: BudgetTransaction[];
  members: BudgetMember[];
  search: string;
  onSearch: (search: string) => void;
  onDelete: (id: string) => void;
}) {
  const memberById = new Map(members.map((member) => [member.id, member]));
  const filteredTransactions = transactions.filter((transaction) =>
    `${transaction.title} ${categoryName(transaction.category)}`
      .toLowerCase()
      .includes(search.trim().toLowerCase())
  );

  return (
    <section className="stack-view">
      <div className="toolbar">
        <label className="search-control">
          <Search size={17} aria-hidden="true" />
          <input
            value={search}
            onChange={(event) => onSearch(event.target.value)}
            placeholder="Search transactions"
            aria-label="Search transactions"
          />
        </label>
        <span>{filteredTransactions.length} shown</span>
      </div>
      <div className="panel table-panel">
        {filteredTransactions.length === 0 ? (
          <div className="empty-state">No transactions in this view.</div>
        ) : (
          filteredTransactions.map((transaction) => (
            <article key={transaction.id} className="transaction-row">
              <div className={`transaction-icon ${transaction.type}`}>
                {transaction.type === "income" ? (
                  <ArrowUpCircle size={19} aria-hidden="true" />
                ) : (
                  <ArrowDownCircle size={19} aria-hidden="true" />
                )}
              </div>
              <div className="transaction-main">
                <strong>{transaction.title}</strong>
                <span>
                  {categoryName(transaction.category)} ·{" "}
                  {memberById.get(transaction.createdByMemberId)?.displayName ?? "Member"}
                </span>
              </div>
              <div className="transaction-amount">
                <strong>
                  {transaction.type === "expense" ? "-" : "+"}
                  {formatMoney(transaction.amount, settings.currencyCode)}
                </strong>
                <span>{new Date(transaction.date).toLocaleDateString()}</span>
              </div>
              <button
                className="icon-button subtle"
                onClick={() => onDelete(transaction.id)}
                title="Delete transaction"
                aria-label={`Delete ${transaction.title}`}
                type="button"
              >
                <Trash2 size={17} aria-hidden="true" />
              </button>
            </article>
          ))
        )}
      </div>
    </section>
  );
}

function BudgetView({
  settings,
  totals,
  transactions,
  members,
  onSettingsChange
}: {
  settings: BudgetSettings;
  totals: ReturnType<typeof dashboardTotals>;
  transactions: BudgetTransaction[];
  members: BudgetMember[];
  onSettingsChange: (settings: BudgetSettings) => void;
}) {
  const spending = categoryBreakdown(transactions);
  const spendingByCategory = new Map(spending.map((item) => [item.category, item.amount]));
  const memberSpending = memberExpenseTotals(transactions, members);

  function updateCategoryBudget(category: string, value: string) {
    onSettingsChange({
      ...settings,
      categoryBudgets: {
        ...settings.categoryBudgets,
        [category]: normalizeAmount(Number(value))
      }
    });
  }

  return (
    <section className="budget-layout">
      <section className="panel">
        <div className="panel-heading">
          <h2>Category budgets</h2>
          <span>{formatMoney(totals.remainingBudget, settings.currencyCode)} left</span>
        </div>
        <div className="budget-list">
          {expenseCategories.map((category) => (
            <div key={category.id} className="budget-row">
              <div>
                <strong>{category.name}</strong>
                <span>{formatMoney(spendingByCategory.get(category.id) ?? 0, settings.currencyCode)} spent</span>
              </div>
              <input
                type="number"
                min="0"
                step="10"
                value={settings.categoryBudgets[category.id] ?? 0}
                onChange={(event) => updateCategoryBudget(category.id, event.target.value)}
                aria-label={`${category.name} budget`}
              />
            </div>
          ))}
        </div>
      </section>

      <aside className="panel member-spending">
        <div className="panel-heading">
          <h2>Member spending</h2>
          <span>{members.length} members</span>
        </div>
        {memberSpending.map(({ member, amount }) => (
          <div key={member.id} className="member-spend-row">
            <MemberBadge member={member} />
            <div>
              <strong>{member.displayName}</strong>
              <span>{formatMoney(amount, settings.currencyCode)}</span>
            </div>
          </div>
        ))}
      </aside>
    </section>
  );
}

function SettingsView({
  settings,
  state,
  members,
  importText,
  importError,
  syncMode,
  user,
  cloudMessage,
  cloudError,
  pendingInvites,
  onSettingsChange,
  onAddMember,
  onImportTextChange,
  onImport,
  onReset,
  onRefresh,
  onSignOut,
  onCreateSharedBudget,
  onAcceptInvite
}: {
  settings: BudgetSettings;
  state: AppState;
  members: BudgetMember[];
  importText: string;
  importError: string;
  syncMode: SyncMode;
  user?: User;
  cloudMessage: string;
  cloudError: string;
  pendingInvites: BudgetInvite[];
  onSettingsChange: (settings: BudgetSettings) => void;
  onAddMember: (name: string, email: string) => void;
  onImportTextChange: (value: string) => void;
  onImport: () => void;
  onReset: () => void;
  onRefresh: () => void;
  onSignOut: () => void;
  onCreateSharedBudget: (name: string) => void;
  onAcceptInvite: (invite: BudgetInvite) => void;
}) {
  const [memberName, setMemberName] = useState("");
  const [memberEmail, setMemberEmail] = useState("");
  const [sharedBudgetName, setSharedBudgetName] = useState("");
  const [memberMessage, setMemberMessage] = useState("");
  const [sharedBudgetMessage, setSharedBudgetMessage] = useState("");

  function handleAddMember(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedName = memberName.trim();
    const trimmedEmail = memberEmail.trim();

    if (!trimmedName) {
      setMemberMessage("Enter a member name before adding them.");
      return;
    }

    onAddMember(trimmedName, trimmedEmail);
    setMemberName("");
    setMemberEmail("");
    setMemberMessage(
      trimmedEmail && syncMode !== "cloud"
        ? "Member added locally. Turn on cloud sync to send email invites."
        : trimmedEmail
          ? "Invite saved."
          : "Member added."
    );
  }

  function handleCreateSharedBudget(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedName = sharedBudgetName.trim();

    if (syncMode !== "cloud") {
      setSharedBudgetMessage("Cloud sync is required to create shared budgets.");
      return;
    }

    if (!trimmedName) {
      setSharedBudgetMessage("Enter a shared budget name before creating it.");
      return;
    }

    onCreateSharedBudget(trimmedName);
    setSharedBudgetName("");
    setSharedBudgetMessage("Creating shared budget.");
  }

  const sharedBudgetNote =
    sharedBudgetMessage ||
    (syncMode !== "cloud"
      ? "Turn on cloud sync to create shared budgets."
      : sharedBudgetName.trim()
        ? "Ready to create a shared household budget."
        : "Enter a name to create a shared budget.");
  const memberNote =
    memberMessage ||
    (memberName.trim()
      ? memberEmail.trim() && syncMode !== "cloud"
        ? "This member will be added locally until cloud sync is active."
        : "Ready to add this member."
      : syncMode === "cloud"
        ? "Enter a name to add someone. Email is optional."
        : "Enter a name to add someone locally.");

  return (
    <section className="settings-grid">
      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Account</h2>
          {syncMode === "cloud" ? <Cloud size={18} aria-hidden="true" /> : <HardDrive size={18} aria-hidden="true" />}
        </div>
        <div className="status-row">
          {syncMode === "cloud" ? <CheckCircle2 size={18} aria-hidden="true" /> : <HardDrive size={18} aria-hidden="true" />}
          <div>
            <strong>{syncMode === "cloud" ? user?.email ?? "Signed in" : "Desktop local"}</strong>
            <span>{cloudError || cloudMessage}</span>
          </div>
        </div>
        <div className="data-actions">
          <button className="secondary-action" onClick={onRefresh} disabled={syncMode !== "cloud"}>
            <RefreshCcw size={17} aria-hidden="true" />
            Refresh
          </button>
          <button className="secondary-action quiet" onClick={onSignOut} disabled={syncMode !== "cloud"}>
            <LogOut size={17} aria-hidden="true" />
            Sign out
          </button>
        </div>
      </section>

      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Preferences</h2>
          <SlidersHorizontal size={18} aria-hidden="true" />
        </div>
        <label className="field-row">
          <span>Currency</span>
          <select
            value={settings.currencyCode}
            onChange={(event) => onSettingsChange({ ...settings, currencyCode: event.target.value })}
          >
            {currencyOptions.map((currency) => (
              <option key={currency.code} value={currency.code}>
                {currency.code} - {currency.name}
              </option>
            ))}
          </select>
        </label>
        <div className="status-row">
          <RefreshCcw size={18} aria-hidden="true" />
          <div>
            <strong>Cloud backup</strong>
            <span>
              {syncMode === "cloud"
                ? cloudError || cloudMessage
                : supabaseConfigStatus === "configured"
                  ? "Supabase configured"
                  : "Ready for Supabase config"}
            </span>
          </div>
        </div>
      </section>

      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Households</h2>
          <span>{state.budgets.length}</span>
        </div>
        <div className="member-list">
          {state.budgets.map((budget) => (
            <div key={budget.id} className="member-row">
              <span className="household-mark">
                <Home size={16} aria-hidden="true" />
              </span>
              <div>
                <strong>{budget.name}</strong>
                <span>{budget.id === state.currentUserId ? "Personal" : "Shared"}</span>
              </div>
            </div>
          ))}
        </div>
        <form className="member-form household-form" onSubmit={handleCreateSharedBudget}>
          <input
            value={sharedBudgetName}
            onChange={(event) => {
              setSharedBudgetName(event.target.value);
              setSharedBudgetMessage("");
            }}
            placeholder="Shared budget name"
            aria-label="Shared budget name"
            aria-describedby="shared-budget-note"
          />
          <button className="secondary-action" type="submit" disabled={syncMode !== "cloud" || !sharedBudgetName.trim()}>
            <Plus size={17} aria-hidden="true" />
            Create
          </button>
        </form>
        <p className="form-note" id="shared-budget-note" role="status" aria-live="polite">
          {sharedBudgetNote}
        </p>
      </section>

      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Members</h2>
          <span>{members.length}</span>
        </div>
        <div className="member-list">
          {members.map((member) => (
            <div key={member.id} className="member-row">
              <MemberBadge member={member} />
              <div>
                <strong>{member.displayName}</strong>
                <span>{member.inviteStatus}</span>
              </div>
            </div>
          ))}
        </div>
        <form className="member-form" onSubmit={handleAddMember}>
          <input
            value={memberName}
            onChange={(event) => {
              setMemberName(event.target.value);
              setMemberMessage("");
            }}
            placeholder="Member name"
            aria-label="Member name"
            aria-describedby="member-form-note"
          />
          <input
            value={memberEmail}
            onChange={(event) => {
              setMemberEmail(event.target.value);
              setMemberMessage("");
            }}
            placeholder="Email"
            aria-label="Member email"
            aria-describedby="member-form-note"
          />
          <button className="secondary-action" type="submit" disabled={!memberName.trim()}>
            <Plus size={17} aria-hidden="true" />
            Add
          </button>
        </form>
        <p className="form-note" id="member-form-note" role="status" aria-live="polite">
          {memberNote}
        </p>
      </section>

      {syncMode === "cloud" && (
        <section className="panel settings-panel">
          <div className="panel-heading">
            <h2>Invites</h2>
            <span>{pendingInvites.length}</span>
          </div>
          {pendingInvites.length === 0 ? (
            <div className="empty-state">No pending invites.</div>
          ) : (
            <div className="member-list">
              {pendingInvites.map((invite) => (
                <div key={invite.id} className="invite-row">
                  <div>
                    <strong>{invite.displayName}</strong>
                    <span>{invite.email}</span>
                  </div>
                  <button className="secondary-action" onClick={() => onAcceptInvite(invite)}>
                    Accept
                  </button>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      <section className="panel settings-panel data-panel">
        <div className="panel-heading">
          <h2>Data</h2>
          <span>{syncMode === "cloud" ? "Cached" : "Local"}</span>
        </div>
        <textarea readOnly value={exportState(state)} aria-label="Exported BudgetMate data" />
        <div className="data-actions">
          <a
            className="secondary-action"
            href={`data:application/json;charset=utf-8,${encodeURIComponent(exportState(state))}`}
            download="budgetmate-web-data.json"
          >
            <Download size={17} aria-hidden="true" />
            Export
          </a>
          <button className="danger-action" onClick={onReset}>
            <RefreshCcw size={17} aria-hidden="true" />
            Reset
          </button>
        </div>
        <textarea
          value={importText}
          onChange={(event) => onImportTextChange(event.target.value)}
          placeholder="Paste exported data"
          aria-label="Import BudgetMate data"
        />
        {importError && <p className="form-error" role="alert">{importError}</p>}
        <button className="secondary-action" onClick={onImport}>
          <Upload size={17} aria-hidden="true" />
          Import
        </button>
      </section>
    </section>
  );
}

function TransactionDialog({
  members,
  onClose,
  onSubmit
}: {
  members: BudgetMember[];
  onClose: () => void;
  onSubmit: (form: TransactionFormState) => void;
}) {
  const [form, setForm] = useState<TransactionFormState>({
    type: "expense",
    title: "",
    amount: "",
    category: "groceries",
    paymentMethod: "card",
    createdByMemberId: members[0]?.id ?? "",
    date: todayInputValue(),
    splitWithHousehold: false
  });
  const [formError, setFormError] = useState("");
  const dialogRef = useRef<HTMLFormElement | null>(null);

  const categories = form.type === "income" ? incomeCategories : expenseCategories;

  useEffect(() => {
    function focusableElements() {
      return Array.from(
        dialogRef.current?.querySelectorAll<HTMLElement>(
          'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [href], [tabindex]:not([tabindex="-1"])'
        ) ?? []
      ).filter((element) => element.offsetWidth > 0 || element.offsetHeight > 0 || element.getClientRects().length > 0);
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
        return;
      }

      if (event.key !== "Tab") {
        return;
      }

      const elements = focusableElements();
      if (elements.length === 0) {
        event.preventDefault();
        return;
      }

      const first = elements[0];
      const last = elements[elements.length - 1];
      const active = document.activeElement;

      if (event.shiftKey && active === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      } else if (!dialogRef.current?.contains(active)) {
        event.preventDefault();
        first.focus();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  function updateForm(patch: Partial<TransactionFormState>) {
    setFormError("");
    setForm((current) => {
      const next = { ...current, ...patch };
      if (patch.type) {
        next.category = patch.type === "income" ? "work" : "groceries";
        next.splitWithHousehold = false;
      }
      return next;
    });
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const amount = normalizeAmount(Number(form.amount));
    if (!form.title.trim()) {
      setFormError("Add a title before saving this transaction.");
      return;
    }
    if (amount <= 0) {
      setFormError("Enter an amount greater than zero.");
      return;
    }
    if (!form.date || !form.createdByMemberId) {
      setFormError("Choose a date and member before saving.");
      return;
    }

    setFormError("");
    onSubmit(form);
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <form
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="transaction-dialog-title"
        onMouseDown={(event) => event.stopPropagation()}
        onSubmit={handleSubmit}
        noValidate
        ref={dialogRef}
      >
        <div className="panel-heading">
          <h2 id="transaction-dialog-title">Add transaction</h2>
          <button className="icon-button" onClick={onClose} title="Close" aria-label="Close add transaction" type="button">
            <X size={18} aria-hidden="true" />
          </button>
        </div>

        <div className="segmented" role="group" aria-label="Transaction type">
          <button
            className={form.type === "expense" ? "active" : ""}
            onClick={() => updateForm({ type: "expense" })}
            aria-pressed={form.type === "expense"}
            type="button"
          >
            Expense
          </button>
          <button
            className={form.type === "income" ? "active" : ""}
            onClick={() => updateForm({ type: "income" })}
            aria-pressed={form.type === "income"}
            type="button"
          >
            Income
          </button>
        </div>

        <label className="field-row vertical">
          <span>Title</span>
          <input
            value={form.title}
            onChange={(event) => updateForm({ title: event.target.value })}
            autoFocus
            required
            aria-invalid={!!formError && !form.title.trim()}
            aria-describedby={formError ? "transaction-form-error" : undefined}
          />
        </label>

        <div className="form-grid">
          <label className="field-row vertical">
            <span>Amount</span>
            <input
              type="number"
              min="0"
              step="0.01"
              value={form.amount}
              onChange={(event) => updateForm({ amount: event.target.value })}
              required
              aria-invalid={!!formError && normalizeAmount(Number(form.amount)) <= 0}
              aria-describedby={formError ? "transaction-form-error" : undefined}
            />
          </label>
          <label className="field-row vertical">
            <span>Date</span>
            <input type="date" value={form.date} onChange={(event) => updateForm({ date: event.target.value })} required />
          </label>
        </div>

        <label className="field-row vertical">
          <span>Category</span>
          <select value={form.category} onChange={(event) => updateForm({ category: event.target.value })} required>
            {categories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </label>

        <label className="field-row vertical">
          <span>Member</span>
          <select value={form.createdByMemberId} onChange={(event) => updateForm({ createdByMemberId: event.target.value })} required>
            {members.map((member) => (
              <option key={member.id} value={member.id}>
                {member.displayName}
              </option>
            ))}
          </select>
        </label>

        {form.type === "expense" && (
          <label className="toggle-row">
            <input
              type="checkbox"
              checked={form.splitWithHousehold}
              onChange={(event) => updateForm({ splitWithHousehold: event.target.checked })}
            />
            <span>Split with household</span>
          </label>
        )}

        {formError && (
          <p className="form-error" id="transaction-form-error" role="alert">
            {formError}
          </p>
        )}

        <button className="primary-action full" type="submit">
          <Plus size={18} aria-hidden="true" />
          Add transaction
        </button>
      </form>
    </div>
  );
}

function TransactionList({ transactions, settings }: { transactions: BudgetTransaction[]; settings: BudgetSettings }) {
  return (
    <div className="compact-list">
      {transactions.length === 0 ? (
        <div className="empty-state">No transactions in this view.</div>
      ) : (
        transactions.map((transaction) => (
          <div key={transaction.id} className="compact-row">
            <span className={`dot ${transaction.type}`} />
            <div>
              <strong>{transaction.title}</strong>
              <span>{categoryName(transaction.category)}</span>
            </div>
            <b>
              {transaction.type === "expense" ? "-" : "+"}
              {formatMoney(transaction.amount, settings.currencyCode)}
            </b>
          </div>
        ))
      )}
    </div>
  );
}

function CategoryRow({
  category,
  amount,
  budget,
  currencyCode
}: {
  category: string;
  amount: number;
  budget: number;
  currencyCode: string;
}) {
  const ratio = budget > 0 ? Math.min(1, amount / budget) : 0;

  return (
    <div className="category-row">
      <div>
        <strong>{categoryName(category)}</strong>
        <span>
          {formatMoney(amount, currencyCode)} of {formatMoney(budget, currencyCode)}
        </span>
      </div>
      <div className="mini-progress" aria-hidden="true">
        <span style={{ width: `${ratio * 100}%` }} />
      </div>
    </div>
  );
}

function MemberBadge({ member }: { member: BudgetMember }) {
  return (
    <span className="member-badge" style={{ backgroundColor: member.color }}>
      {member.initials}
    </span>
  );
}

export { App };
