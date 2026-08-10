import {
  ArrowDownCircle,
  ArrowUpCircle,
  Banknote,
  BarChart3,
  CalendarDays,
  CheckCircle2,
  ChevronDown,
  Cloud,
  Download,
  HardDrive,
  Home,
  Lightbulb,
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
import type { CSSProperties, FormEvent, KeyboardEvent as ReactKeyboardEvent } from "react";
import type { Session, User } from "@supabase/supabase-js";
import {
  addCategorySettings,
  categoryColor,
  categoryIdFromDisplayName,
  categoryName,
  contrastTextColor,
  expenseCategories,
  hiddenExpenseCategoryIds,
  incomeCategories,
  isSingleEmoji,
  normalizedCategoryEmoji,
  removeCategorySettings,
  renameCategorySettings,
  unhideCategorySettings,
  updateCategoryEmojiSettings,
  visibleExpenseCategories
} from "./domain/categories";
import { amountFromMinorUnits, amountMinorUnits, currencyOptions, currencySymbol, formatAmountNumber, formatMoney, normalizedCurrencyCode } from "./domain/currency";
import { localDateKey, localNoonISOString } from "./domain/dates";
import {
  authEntryIsVisible,
  deriveHouseholdCapabilities,
  householdOwnerOnlyMessage,
  modeAfterSignOut,
  type HouseholdCapabilities
} from "./domain/householdCapabilities";
import {
  currencyChangeDecision,
  currencyFinancialHistoryState,
  recordMutationDecision,
  sharedRecordMutationReadOnlyMessage
} from "./domain/financialSafety";
import {
  categoryBreakdown,
  currentMonthKey,
  dashboardTotals,
  involvesMember,
  memberExpenseTotals,
  monthBudgetKey,
  monthlyBudget,
  normalizeAmount,
  selectedCategoryBudgets,
  settlementExplanation,
  settlementSuggestions,
  transactionsForMonth,
  uniqueTransactions
} from "./domain/budgetMath";
import { defaultBudgetSettings } from "./domain/defaults";
import { memberFilterLabels, organizeCategoryBudgetRows } from "./domain/uxClarity";
import { activeRecurringExpenses, buildMonthlyRecurrence, parseMonthlyRecurrence, previousLocalDate } from "./domain/recurrence";
import { validateProfileName } from "./domain/profile";
import { allocateEqualSplitMinorUnits, validateCustomSplitAmounts } from "./domain/splits";
import type {
  AppState,
  BudgetInvite,
  BudgetMember,
  BudgetSettings,
  BudgetTransaction,
  Settlement,
  TransactionSplit,
  TransactionType
} from "./domain/types";
import {
  acceptCloudInvite,
  buildSettlementGateCMutation,
  buildSettlementDeleteGateCMutation,
  buildTransactionDeleteGateCMutation,
  buildTransactionGateCMutation,
  createCloudInvite,
  createCloudSharedBudget,
  fetchCloudState,
  fetchPendingInvites,
  pendingGateCFinancialMutations,
  queueGateCFinancialMutation,
  replayGateCFinancialMutations,
  signInWithEmail,
  signOut,
  signUpWithEmail,
  upsertCloudMember,
  upsertCloudSettings,
} from "./data/cloudRepository";
import type { QueuedGateCFinancialMutation } from "./data/gateCFinancialOutbox";
import { gateCFinancialWritesEnabled, gateCFinancialWritesReadOnlyMessage } from "./data/gateCRollout";
import {
  appStatesEqual,
  clearState,
  cloudStateStorageKey,
  exportState,
  importState,
  loadCloudState,
  loadState,
  localStateStorageKey,
  resetState,
  saveState
} from "./data/storage";
import { supabase, supabaseConfigStatus } from "./data/supabaseClient";

type Tab = "dashboard" | "transactions" | "budget" | "settings";
type SyncMode = "cloud" | "local";
type SplitMethod = "equal" | "custom";

type CategorySaveInput = {
  oldCategoryId?: string;
  displayName: string;
  emoji?: string;
};

type TransactionFormState = {
  type: TransactionType;
  title: string;
  amount: string;
  category: string;
  paymentMethod?: "cash" | "card" | "paypal";
  createdByMemberId: string;
  date: string;
  splitEnabled: boolean;
  splitMethod: SplitMethod;
  splitMemberIds: string[];
  splitAmounts: Record<string, string>;
  recurrenceEnabled: boolean;
  recurrenceEndDate: string;
};

const todayInputValue = () => localDateKey();
const makeId = () => crypto.randomUUID();
const CLOUD_FALLBACK_REFRESH_INTERVAL_MS = 60_000;
const CLOUD_INVALIDATION_DEBOUNCE_MS = 250;

function transactionSplitsForForm(
  form: TransactionFormState,
  totalMinorUnits: number,
  currencyCode: string,
  existingSplits: TransactionSplit[] = []
): TransactionSplit[] | undefined {
  if (form.type !== "expense" || !form.splitEnabled) {
    return [];
  }

  let allocations;
  if (form.splitMethod === "equal") {
    allocations = allocateEqualSplitMinorUnits(totalMinorUnits, form.splitMemberIds, form.createdByMemberId);
  } else {
    const validation = validateCustomSplitAmounts(totalMinorUnits, form.splitMemberIds, form.splitAmounts, currencyCode);
    if (validation.status !== "valid") {
      return undefined;
    }
    allocations = form.splitMemberIds.map((memberId) => ({
      memberId,
      amountMinorUnits: amountMinorUnits(form.splitAmounts[memberId] ?? "", currencyCode)
    }));
  }

  if (!allocations || allocations.some((allocation) => allocation.amountMinorUnits === undefined)) {
    return undefined;
  }
  const positiveAllocations = allocations.filter(
    (allocation): allocation is typeof allocation & { amountMinorUnits: number } =>
      typeof allocation.amountMinorUnits === "number" && allocation.amountMinorUnits > 0
  );
  if (positiveAllocations.length !== allocations.length) {
    return undefined;
  }
  const existingByMemberId = new Map(existingSplits.map((split) => [split.memberId, split]));
  return positiveAllocations.map((allocation) => ({
    id: existingByMemberId.get(allocation.memberId)?.id ?? makeId(),
    memberId: allocation.memberId,
    amountMinorUnits: allocation.amountMinorUnits,
    currencyCode,
    amount: amountFromMinorUnits(allocation.amountMinorUnits, currencyCode)
  }));
}

type CloudRefreshRequest = {
  preferredBudgetId: string;
  background: boolean;
};

type PendingSettingsWrite = {
  latest?: BudgetSettings;
  userId: string;
};

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

function normalizedEmail(email: string) {
  return email.trim().toLowerCase();
}

function firstName(name: string): string {
  return name.trim().split(/\s+/)[0] || name;
}

function formatMonthLabel(monthKeyValue: string): string {
  const [year, month] = monthKeyValue.split("-").map(Number);
  if (!year || !month) {
    return monthKeyValue;
  }
  return new Date(year, month - 1, 1).toLocaleDateString("en-US", {
    month: "long",
    year: "numeric"
  });
}

function netScopeLabel(monthKeyValue: string): string {
  return monthKeyValue === currentMonthKey() ? "Net this month" : `Net for ${formatMonthLabel(monthKeyValue)}`;
}

function formatDateLabel(value: string): string {
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric"
  });
}

function formatShortDate(value: string): string {
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric"
  });
}

function recurrenceSummary(rule?: string): string {
  if (!rule) {
    return "Does not repeat";
  }
  const recurrence = parseMonthlyRecurrence(rule);
  if (!recurrence) {
    return rule;
  }
  return recurrence.until ? `Monthly · through ${formatDateLabel(`${recurrence.until}T12:00:00`)}` : "Monthly";
}

function daysLeftInMonth(monthKeyValue: string): number {
  const [year, month] = monthKeyValue.split("-").map(Number);
  if (!year || !month) {
    return 0;
  }
  const today = new Date();
  const lastDay = new Date(year, month, 0);
  if (today > lastDay) {
    return 0;
  }
  if (today.getFullYear() !== year || today.getMonth() !== month - 1) {
    return lastDay.getDate();
  }
  return Math.max(0, lastDay.getDate() - today.getDate());
}

function categoryPillStyle(category: string): CSSProperties {
  const color = categoryColor(category);
  return {
    "--category-color": color
  } as CSSProperties;
}

function budgetPaceTone(spent: number, budget: number): "good" | "watch" | "over" {
  if (budget <= 0) {
    return "good";
  }
  const ratio = spent / budget;
  if (ratio >= 1) {
    return "over";
  }
  if (ratio >= 0.8) {
    return "watch";
  }
  return "good";
}

function activateTransactionOnKeyDown(event: ReactKeyboardEvent, onOpen: () => void) {
  if (event.target !== event.currentTarget) {
    return;
  }
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    onOpen();
  }
}

function App() {
  const [state, setState] = useState<AppState>(() => loadState());
  const [syncMode, setSyncMode] = useState<SyncMode>(supabaseConfigStatus === "configured" ? "cloud" : "local");
  const [session, setSession] = useState<Session | null>(null);
  const [authLoading, setAuthLoading] = useState(supabaseConfigStatus === "configured");
  const [isCloudLoading, setIsCloudLoading] = useState(false);
  const [cloudMessage, setCloudMessage] = useState(
    supabaseConfigStatus === "configured" ? "Sign in to sync with Supabase." : "Saved on this device"
  );
  const [cloudError, setCloudError] = useState("");
  const [pendingInvites, setPendingInvites] = useState<BudgetInvite[]>([]);
  const [verifiedCloudBudgetIds, setVerifiedCloudBudgetIds] = useState<string[]>([]);
  const [isCloudSyncing, setIsCloudSyncing] = useState(false);
  const [activeTab, setActiveTab] = useState<Tab>("dashboard");
  const [selectedMonth, setSelectedMonth] = useState(currentMonthKey());
  const [selectedMemberId, setSelectedMemberId] = useState<string>("all");
  const [isAddingTransaction, setIsAddingTransaction] = useState(false);
  const [selectedTransaction, setSelectedTransaction] = useState<BudgetTransaction | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [isSettlementHistoryOpen, setIsSettlementHistoryOpen] = useState(false);
  const [editingTransaction, setEditingTransaction] = useState<BudgetTransaction | null>(null);
  const [transactionSearch, setTransactionSearch] = useState("");
  const [importText, setImportText] = useState("");
  const [importError, setImportError] = useState("");
  const [toastMessage, setToastMessage] = useState("");
  const cloudRefreshInFlight = useRef<Promise<void> | null>(null);
  const queuedCloudRefresh = useRef<CloudRefreshRequest | null>(null);
  const cloudMutationQueue = useRef<Promise<void>>(Promise.resolve());
  const pendingCloudMutations = useRef(0);
  const cloudDataVersion = useRef(0);
  const activeUserId = useRef<string | null>(null);
  const sessionUser = useRef<User | null>(null);
  const syncModeRef = useRef<SyncMode>(syncMode);
  const currentBudgetIdRef = useRef(state.currentBudgetId);
  const settingsWrites = useRef(new Map<string, PendingSettingsWrite>());
  const addTransactionButtonRef = useRef<HTMLButtonElement | null>(null);

  sessionUser.current = session?.user ?? null;
  syncModeRef.current = syncMode;
  currentBudgetIdRef.current = state.currentBudgetId;

  const canUseCloud = syncMode === "cloud" && !!session?.user && !!supabase;
  const activeStorageKey =
    syncMode === "cloud" && session?.user ? cloudStateStorageKey(session.user.id) : localStateStorageKey;
  const canPersistState = syncMode === "local" || (!!session?.user && state.currentUserId === session.user.id);
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
  useEffect(() => {
    document.documentElement.dataset.theme = settings.appearance;
    return () => {
      delete document.documentElement.dataset.theme;
    };
  }, [settings.appearance]);
  const budgetMembers = useMemo(
    () => state.members.filter((member) => member.budgetId === currentBudget.id),
    [state.members, currentBudget.id]
  );
  const householdIdentity = session?.user
    ? { id: session.user.id, email: session.user.email }
    : syncMode === "local"
      ? { id: state.currentUserId }
      : undefined;
  const householdCapabilities = deriveHouseholdCapabilities(currentBudget, budgetMembers, householdIdentity);
  const currentBudgetMember = householdCapabilities.currentMember;
  const budgetTransactions = useMemo(
    () => uniqueTransactions(state.transactions.filter((transaction) => transaction.budgetId === currentBudget.id)),
    [state.transactions, currentBudget.id]
  );
  const budgetSettlements = useMemo(
    () => state.settlements.filter((settlement) => settlement.budgetId === currentBudget.id),
    [state.settlements, currentBudget.id]
  );
  const monthTransactions = useMemo(
    () => transactionsForMonth(budgetTransactions, selectedMonth),
    [budgetTransactions, selectedMonth]
  );
  const memberFilter = selectedMemberId === "all" ? undefined : selectedMemberId;
  const displayedTransactions = useMemo(
    () => monthTransactions.filter((transaction) => (memberFilter ? involvesMember(transaction, memberFilter) : true)),
    [monthTransactions, memberFilter]
  );
  const categoryTransactions = useMemo(
    () => selectedCategory
      ? displayedTransactions.filter((transaction) => transaction.type === "expense" && transaction.category === selectedCategory)
      : [],
    [displayedTransactions, selectedCategory]
  );
  const totals = useMemo(
    () => dashboardTotals(monthTransactions, monthlyBudget(settings, selectedMonth), memberFilter),
    [monthTransactions, settings, selectedMonth, memberFilter]
  );
  const categoryTotals = useMemo(
    () => categoryBreakdown(monthTransactions, memberFilter),
    [monthTransactions, memberFilter]
  );
  const settlements = useMemo(
    () => settlementSuggestions(budgetTransactions, budgetSettlements, budgetMembers),
    [budgetTransactions, budgetSettlements, budgetMembers]
  );
  const cloudFinancialWritesReadOnly = syncMode === "cloud" && !gateCFinancialWritesEnabled;
  const financialMutationUserId = session?.user.id ?? state.currentUserId;
  const currencyHistoryVerification =
    syncMode === "local"
      ? "verified"
      : cloudError
        ? "unverified"
        : isCloudSyncing ||
            !verifiedCloudBudgetIds.includes(currentBudget.id) ||
            settingsWrites.current.has(currentBudget.id)
          ? "loading"
          : "verified";
  const currentCurrencyChangeDecision = currencyChangeDecision({
    activeBudgetId: currentBudget.id,
    presentedBudgetId: currentBudget.id,
    history: currencyFinancialHistoryState({
      transactionCount: budgetTransactions.length,
      settlementCount: budgetSettlements.length,
      categoryBudgetKeys: Object.keys(settings.categoryBudgets)
    }),
    verification: currencyHistoryVerification
  });
  const currencyCanChange = householdCapabilities.canEditCurrency && currentCurrencyChangeDecision.isAllowed;
  const currencyRestrictionMessage = householdCapabilities.canEditCurrency
    ? currentCurrencyChangeDecision.restrictionMessage ?? "Choose the household currency before adding financial activity. Saved amounts are not converted later."
    : householdOwnerOnlyMessage;
  function recordCapability(
    recordBudgetId: string,
    operation: "create" | "modifyExisting",
    recordCreatorUserId?: string,
    legacyRecordCreatorUserId?: string
  ) {
    return recordMutationDecision({
      currentUserId: financialMutationUserId,
      activeBudgetId: currentBudget.id,
      recordBudgetId,
      ownerUserId: currentBudget.ownerUserId,
      members: budgetMembers,
      recordCreatorUserId,
      legacyRecordCreatorUserId,
      operation,
      serverGateEnabled: !cloudFinancialWritesReadOnly
    });
  }
  const canCreateFinancialRecord = recordCapability(currentBudget.id, "create").isAllowed;
  const financialMutationReadOnlyMessage = cloudFinancialWritesReadOnly
    ? gateCFinancialWritesReadOnlyMessage
    : sharedRecordMutationReadOnlyMessage;

  function transactionMutationDecision(transaction: BudgetTransaction) {
    return recordCapability(
      transaction.budgetId,
      "modifyExisting",
      transaction.createdByUserId,
      transaction.userId
    );
  }
  function settlementMutationDecision(settlement: Settlement) {
    return recordCapability(
      settlement.budgetId,
      "modifyExisting",
      settlement.createdByUserId,
      settlement.userId
    );
  }
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
      const nextUserId = data.session?.user.id ?? null;
      const isAccountTransition = nextUserId !== activeUserId.current;
      activeUserId.current = nextUserId;
      sessionUser.current = data.session?.user ?? null;
      setSession(data.session);
      if (data.session?.user && isAccountTransition) {
        setVerifiedCloudBudgetIds([]);
        setState(loadCloudState(data.session.user.id));
      }
      setAuthLoading(false);
    });

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (!isMounted) {
        return;
      }
      const nextUserId = nextSession?.user.id ?? null;
      const isAccountTransition = nextUserId !== activeUserId.current;
      activeUserId.current = nextUserId;
      sessionUser.current = nextSession?.user ?? null;
      setSession(nextSession);
      if (nextSession?.user) {
        syncModeRef.current = "cloud";
        setSyncMode("cloud");
        if (isAccountTransition) {
          setVerifiedCloudBudgetIds([]);
          setState(loadCloudState(nextSession.user.id));
          setCloudMessage("Signed in. Loading cloud data.");
        }
      }
      if (!nextSession) {
        setPendingInvites([]);
        setVerifiedCloudBudgetIds([]);
        setCloudMessage("You are signed out. Sign in to continue, or use this computer for local mode.");
      }
      setAuthLoading(false);
    });

    return () => {
      isMounted = false;
      data.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!canPersistState) {
      return;
    }
    saveState(state, activeStorageKey);
  }, [activeStorageKey, canPersistState, state]);

  useEffect(() => {
    const handleStorage = (event: StorageEvent) => {
      if (event.storageArea !== window.localStorage || event.key !== activeStorageKey) {
        return;
      }

      if (syncModeRef.current === "cloud") {
        const user = sessionUser.current;
        if (!user || pendingCloudMutations.current > 0) {
          return;
        }
        if (!event.newValue) {
          void reloadCloudState(currentBudgetIdRef.current, { background: true });
          return;
        }
        const cachedState = loadState(activeStorageKey);
        if (cachedState.currentUserId !== user.id) {
          return;
        }
        setState((current) => (appStatesEqual(current, cachedState) ? current : cachedState));
        cloudDataVersion.current += 1;
        void reloadCloudState(currentBudgetIdRef.current, { background: true });
        return;
      }

      const localState = loadState(localStateStorageKey);
      setState((current) => (appStatesEqual(current, localState) ? current : localState));
    };

    window.addEventListener("storage", handleStorage);
    return () => window.removeEventListener("storage", handleStorage);
  }, [activeStorageKey]);

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
    const client = supabase;
    if (!canUseCloud || !client) {
      return;
    }

    let refreshTimer: number | undefined;
    const scheduleRefresh = () => {
      if (document.visibilityState !== "visible" || !navigator.onLine) {
        return;
      }
      if (refreshTimer !== undefined) {
        window.clearTimeout(refreshTimer);
      }
      refreshTimer = window.setTimeout(() => {
        refreshTimer = undefined;
        void reloadCloudState(currentBudgetIdRef.current, { background: true });
      }, CLOUD_INVALIDATION_DEBOUNCE_MS);
    };

    const channel = client.channel(`budgetmate-web-${session?.user.id}-${crypto.randomUUID()}`);
    [
      "budgets",
      "budget_memberships",
      "budget_members",
      "budget_settings",
      "budget_transactions",
      "budget_settlements",
      "budget_invites"
    ].forEach((table) => {
      channel.on("postgres_changes", { event: "*", schema: "public", table }, scheduleRefresh);
    });
    channel.subscribe();

    const intervalId = window.setInterval(scheduleRefresh, CLOUD_FALLBACK_REFRESH_INTERVAL_MS);
    window.addEventListener("focus", scheduleRefresh);
    window.addEventListener("online", scheduleRefresh);
    document.addEventListener("visibilitychange", scheduleRefresh);

    return () => {
      if (refreshTimer !== undefined) {
        window.clearTimeout(refreshTimer);
      }
      window.clearInterval(intervalId);
      window.removeEventListener("focus", scheduleRefresh);
      window.removeEventListener("online", scheduleRefresh);
      document.removeEventListener("visibilitychange", scheduleRefresh);
      void client.removeChannel(channel);
    };
  }, [canUseCloud, session?.user.id]);

  async function reloadCloudState(
    preferredBudgetId = currentBudgetIdRef.current,
    options: { background?: boolean } = {}
  ): Promise<void> {
    if (!sessionUser.current || syncModeRef.current !== "cloud") {
      return;
    }

    const existingRequest = queuedCloudRefresh.current;
    queuedCloudRefresh.current = {
      preferredBudgetId,
      background: (existingRequest?.background ?? true) && !!options.background
    };

    if (cloudRefreshInFlight.current) {
      return cloudRefreshInFlight.current;
    }

    let showedLoading = false;
    const drainRefreshes = async () => {
      while (queuedCloudRefresh.current) {
        const request = queuedCloudRefresh.current;
        queuedCloudRefresh.current = null;

        if (pendingCloudMutations.current > 0) {
          await cloudMutationQueue.current;
        }

        const activeUser = sessionUser.current;
        if (!activeUser || syncModeRef.current !== "cloud") {
          continue;
        }

        if (!request.background) {
          showedLoading = true;
          setIsCloudLoading(true);
          setCloudError("");
        }

        const refreshVersion = cloudDataVersion.current;
        try {
          if (gateCFinancialWritesEnabled) {
            const replayed = await replayGateCFinancialMutations(activeUser.id);
            if (replayed.length > 0) {
              cloudDataVersion.current += 1;
              setCloudMessage(`Saved ${replayed.length} pending financial ${replayed.length === 1 ? "change" : "changes"}`);
            }
          } else if (pendingGateCFinancialMutations(activeUser.id).length > 0) {
            setCloudMessage("Pending financial changes are deferred until this build is approved for Gate C writes.");
          }

          setVerifiedCloudBudgetIds([]);
          const [nextState, invites] = await Promise.all([
            fetchCloudState(activeUser, request.preferredBudgetId),
            fetchPendingInvites(activeUser.email ?? "")
          ]);

          if (
            sessionUser.current?.id !== activeUser.id ||
            syncModeRef.current !== "cloud"
          ) {
            continue;
          }

          if (refreshVersion !== cloudDataVersion.current || pendingCloudMutations.current > 0) {
            if (!queuedCloudRefresh.current) {
              queuedCloudRefresh.current = {
                preferredBudgetId: currentBudgetIdRef.current,
                background: true
              };
            }
            continue;
          }

          setState((current) => (appStatesEqual(current, nextState) ? current : nextState));
          setVerifiedCloudBudgetIds(nextState.budgets.map((budget) => budget.id));
          setPendingInvites(invites);
          setCloudError("");
          setCloudMessage("Synced just now");
        } catch (error) {
          if (sessionUser.current?.id !== activeUser.id) {
            continue;
          }
          const message = error instanceof Error ? error.message : "Cloud sync failed.";
          setCloudError(message);
          setCloudMessage("Needs attention");
        }
      }
    };

    const refresh = (async () => {
      setIsCloudSyncing(true);
      try {
        do {
          await drainRefreshes();
        } while (queuedCloudRefresh.current);
      } finally {
        cloudRefreshInFlight.current = null;
        if (showedLoading) {
          setIsCloudLoading(false);
        }
        setIsCloudSyncing(false);
      }
    })();
    cloudRefreshInFlight.current = refresh;
    return refresh;
  }

  function runCloudMutation(action: () => Promise<void>, successMessage = "Synced just now"): Promise<boolean> {
    const userId = sessionUser.current?.id;
    if (!userId || syncModeRef.current !== "cloud" || !supabase) {
      return Promise.resolve(false);
    }

    cloudDataVersion.current += 1;
    pendingCloudMutations.current += 1;
    setCloudError("");
    setCloudMessage("Syncing");

    const execute = async () => {
      let succeeded = false;
      try {
        if (sessionUser.current?.id !== userId || syncModeRef.current !== "cloud") {
          return false;
        }
        await action();
        succeeded = true;
        return true;
      } catch (error) {
        if (sessionUser.current?.id === userId) {
          const message = error instanceof Error ? error.message : "Cloud write failed.";
          setCloudError(message);
          setCloudMessage("Needs attention");
        }
        return false;
      } finally {
        pendingCloudMutations.current = Math.max(0, pendingCloudMutations.current - 1);
        if (
          sessionUser.current?.id === userId &&
          syncModeRef.current === "cloud" &&
          pendingCloudMutations.current === 0
        ) {
          if (succeeded) {
            setCloudMessage(successMessage);
          }
          void reloadCloudState(currentBudgetIdRef.current, { background: true });
        }
      }
    };

    const operation = cloudMutationQueue.current.then(execute, execute);
    cloudMutationQueue.current = operation.then(() => undefined, () => undefined);
    return operation;
  }

  function queueFinancialMutation(createMutation: () => QueuedGateCFinancialMutation) {
    try {
      queueGateCFinancialMutation(createMutation());
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Financial change could not be queued safely.";
      setCloudError(message);
      setCloudMessage("Needs attention");
      setToastMessage(message);
      return false;
    }
  }

  function updateSettings(nextSettings: BudgetSettings, persistToCloud = true) {
    const changesCurrentHouseholdCurrency =
      nextSettings.budgetId === currentBudget.id && nextSettings.currencyCode !== settings.currencyCode;
    if (changesCurrentHouseholdCurrency && !householdCapabilities.canEditCurrency) {
      setToastMessage(householdOwnerOnlyMessage);
      return;
    }
    if (changesCurrentHouseholdCurrency) {
      const decision = currencyChangeDecision({
        activeBudgetId: currentBudget.id,
        presentedBudgetId: currentBudget.id,
        history: currencyFinancialHistoryState({
          transactionCount: budgetTransactions.length,
          settlementCount: budgetSettlements.length,
          categoryBudgetKeys: Array.from(new Set([
            ...Object.keys(settings.categoryBudgets),
            ...Object.keys(nextSettings.categoryBudgets)
          ]))
        }),
        verification: currencyHistoryVerification
      });
      if (!decision.isAllowed) {
        setToastMessage(decision.restrictionMessage ?? "Currency change is unavailable.");
        return;
      }
    }

    setState((current) => ({
      ...current,
      settingsByBudgetId: {
        ...current.settingsByBudgetId,
        [nextSettings.budgetId]: nextSettings
      }
    }));

    if (persistToCloud) {
      queueSettingsWrite(nextSettings);
    }
  }

  function updateProfileName(name: string): string | undefined {
    const validationMessage = validateProfileName(name);
    if (validationMessage) {
      setToastMessage(validationMessage);
      return validationMessage;
    }

    const authenticatedUserId = syncMode === "cloud" ? session?.user.id : state.currentUserId;
    const member = currentBudgetMember;
    if (
      !authenticatedUserId ||
      !householdIdentity ||
      householdIdentity.id !== authenticatedUserId ||
      !member ||
      member.budgetId !== currentBudget.id ||
      member.inviteStatus !== "active"
    ) {
      const message = "Your active profile could not be resolved.";
      setToastMessage(message);
      return message;
    }

    const updatedMember: BudgetMember = {
      ...member,
      displayName: name.trim(),
      initials: memberInitials(name)
    };
    setState((current) => ({
      ...current,
      members: current.members.map((candidate) =>
        candidate.id === member.id && candidate.budgetId === currentBudget.id ? updatedMember : candidate
      )
    }));

    if (syncMode === "cloud") {
      void runCloudMutation(() => upsertCloudMember(updatedMember, authenticatedUserId), "Profile saved");
    }
    setToastMessage("Profile name saved");
    return undefined;
  }

  function categoryDefinitionsForManagement() {
    const hiddenIds = hiddenExpenseCategoryIds(settings);
    return [
      ...visibleExpenseCategories(settings, budgetTransactions),
      ...expenseCategories.filter((category) => hiddenIds.has(category.id))
    ];
  }

  function commitCategoryChange(
    nextSettings: BudgetSettings,
    moveFrom: string | undefined,
    moveTo: string | undefined,
    successMessage: string
  ): string | undefined {
    const affectedTransactions = moveFrom && moveTo
      ? budgetTransactions.filter((transaction) => transaction.category === moveFrom)
      : [];
    const changedTransactions = affectedTransactions.map((transaction) => ({
      ...transaction,
      category: moveTo as string
    }));

    for (const transaction of affectedTransactions) {
      const decision = transactionMutationDecision(transaction);
      if (!decision.isAllowed) {
        const message = cloudFinancialWritesReadOnly
          ? gateCFinancialWritesReadOnlyMessage
          : decision.readOnlyMessage ?? sharedRecordMutationReadOnlyMessage;
        setToastMessage(message);
        return message;
      }
      if (syncMode === "cloud" && transaction.rowVersion === undefined) {
        const message = "Transaction is not ready to change safely. Refresh cloud data and try again.";
        setToastMessage(message);
        return message;
      }
    }

    if (syncMode === "cloud") {
      for (const transaction of changedTransactions) {
        if (!queueFinancialMutation(() => buildTransactionGateCMutation(transaction, financialMutationUserId))) {
          return "Financial change could not be queued safely.";
        }
      }
    }

    const deferCloudSettingsWrite = syncMode === "cloud" && changedTransactions.length > 0;
    updateSettings(nextSettings, !deferCloudSettingsWrite);
    if (changedTransactions.length > 0) {
      const changedById = new Map(changedTransactions.map((transaction) => [transaction.id, transaction]));
      setState((current) => ({
        ...current,
        transactions: current.transactions.map((transaction) => {
          if (transaction.budgetId !== currentBudget.id || !changedById.has(transaction.id)) {
            return transaction;
          }
          return { ...transaction, category: changedById.get(transaction.id)?.category ?? transaction.category };
        })
      }));
      if (syncMode === "cloud") {
        void runCloudMutation(async () => {
          await replayGateCFinancialMutations(financialMutationUserId);
          await upsertCloudSettings(nextSettings, financialMutationUserId);
        }, "Category saved");
      }
    }
    setToastMessage(successMessage);
    return undefined;
  }

  function saveCategory(input: CategorySaveInput): string | undefined {
    const displayName = input.displayName.trim();
    const categoryId = categoryIdFromDisplayName(displayName);
    if (!categoryId) {
      const message = "Enter a category name.";
      setToastMessage(message);
      return message;
    }
    if (input.oldCategoryId === "other" && categoryId !== "other") {
      const message = "Other cannot be renamed.";
      setToastMessage(message);
      return message;
    }

    const emoji = input.emoji?.trim() ?? "";
    if (emoji && !isSingleEmoji(emoji)) {
      const message = "Use one emoji for the category icon.";
      setToastMessage(message);
      return message;
    }

    const duplicate = categoryDefinitionsForManagement().some((category) => {
      if (category.id === input.oldCategoryId) {
        return false;
      }
      return category.id.toLowerCase() === categoryId.toLowerCase() ||
        category.name.trim().toLowerCase() === displayName.toLowerCase();
    });
    if (duplicate) {
      const message = "That category already exists.";
      setToastMessage(message);
      return message;
    }

    const normalizedEmoji = normalizedCategoryEmoji(emoji);
    let nextSettings: BudgetSettings;
    if (!input.oldCategoryId) {
      nextSettings = addCategorySettings(settings, categoryId, normalizedEmoji);
    } else if (input.oldCategoryId === categoryId) {
      nextSettings = updateCategoryEmojiSettings(settings, categoryId, normalizedEmoji);
    } else {
      nextSettings = renameCategorySettings(settings, input.oldCategoryId, categoryId, normalizedEmoji);
    }

    return commitCategoryChange(
      nextSettings,
      input.oldCategoryId && input.oldCategoryId !== categoryId ? input.oldCategoryId : undefined,
      input.oldCategoryId && input.oldCategoryId !== categoryId ? categoryId : undefined,
      input.oldCategoryId ? "Category updated." : "Category added."
    );
  }

  function removeCategory(categoryId: string): string | undefined {
    if (categoryId === "other") {
      const message = "Other cannot be removed.";
      setToastMessage(message);
      return message;
    }
    return commitCategoryChange(
      removeCategorySettings(settings, categoryId),
      categoryId,
      "other",
      "Category removed. Existing transactions moved to Other."
    );
  }

  function unhideCategory(categoryId: string) {
    const nextSettings = unhideCategorySettings(settings, categoryId);
    updateSettings(nextSettings);
    setToastMessage("Category restored.");
  }

  function queueSettingsWrite(nextSettings: BudgetSettings) {
    const userId = sessionUser.current?.id;
    if (!userId || syncModeRef.current !== "cloud") {
      return;
    }

    const existingWrite = settingsWrites.current.get(nextSettings.budgetId);
    if (existingWrite) {
      existingWrite.latest = nextSettings;
      cloudDataVersion.current += 1;
      setCloudMessage("Syncing");
      return;
    }

    const write: PendingSettingsWrite = { latest: nextSettings, userId };
    settingsWrites.current.set(nextSettings.budgetId, write);
    void runCloudMutation(async () => {
      while (write.latest) {
        const latest = write.latest;
        write.latest = undefined;
        await upsertCloudSettings(latest, write.userId);
      }
    }, "Budget saved").finally(() => {
      if (settingsWrites.current.get(nextSettings.budgetId) === write) {
        settingsWrites.current.delete(nextSettings.budgetId);
      }
      const remaining = write.latest;
      if (remaining) {
        queueSettingsWrite(remaining);
      }
    });
  }

  function addTransaction(form: TransactionFormState) {
    const decision = recordCapability(currentBudget.id, "create");
    if (!decision.isAllowed) {
      setToastMessage(cloudFinancialWritesReadOnly ? gateCFinancialWritesReadOnlyMessage : decision.readOnlyMessage ?? sharedRecordMutationReadOnlyMessage);
      return;
    }
    const amount = normalizeAmount(Number(form.amount));
    const currencyCode = normalizedCurrencyCode(settings.currencyCode);
    const exactAmount = amountMinorUnits(form.amount, currencyCode);
    if (amount <= 0 || exactAmount === undefined || !form.title.trim() || !form.date || !form.createdByMemberId) {
      return;
    }
    const splits = transactionSplitsForForm(form, exactAmount, currencyCode);
    if (!splits) {
      return;
    }
    const recurrenceRule = buildMonthlyRecurrence(form.recurrenceEnabled, form.recurrenceEndDate || undefined);
    if (form.recurrenceEnabled && !recurrenceRule) {
      return;
    }

    const transaction: BudgetTransaction = {
      id: makeId(),
      budgetId: currentBudget.id,
      userId: state.currentUserId,
      createdByUserId: financialMutationUserId,
      title: form.title.trim(),
      amount,
      type: form.type,
      category: form.category,
      paymentMethod: form.type === "expense" ? form.paymentMethod ?? "card" : form.paymentMethod,
      createdByMemberId: form.createdByMemberId,
      date: new Date(`${form.date}T12:00:00`).toISOString(),
      createdAt: new Date().toISOString(),
      recurrenceRule,
      amountMinorUnits: exactAmount,
      currencyCode,
      splits
    };

    if (syncMode === "cloud" && !queueFinancialMutation(() => buildTransactionGateCMutation(transaction, financialMutationUserId))) {
      return;
    }

    setState((current) => ({
      ...current,
      transactions: [transaction, ...current.transactions]
    }));
    setToastMessage("Transaction saved on this device");
    window.setTimeout(() => setToastMessage(""), 2600);
    if (syncMode === "cloud") {
      void runCloudMutation(() => replayGateCFinancialMutations(financialMutationUserId).then(() => undefined));
    }
    setIsAddingTransaction(false);
    window.setTimeout(() => addTransactionButtonRef.current?.focus(), 0);
  }

  function updateTransaction(id: string, form: TransactionFormState) {
    const source = state.transactions.find((candidate) => candidate.id === id);
    if (!source) {
      return;
    }
    const decision = transactionMutationDecision(source);
    if (!decision.isAllowed) {
      setToastMessage(cloudFinancialWritesReadOnly ? gateCFinancialWritesReadOnlyMessage : decision.readOnlyMessage ?? sharedRecordMutationReadOnlyMessage);
      return;
    }

    const currencyCode = source.currencyCode ?? normalizedCurrencyCode(settings.currencyCode);
    const amount = normalizeAmount(Number(form.amount));
    const exactAmount = amountMinorUnits(form.amount, currencyCode);
    if (amount <= 0 || exactAmount === undefined || !form.title.trim() || !form.date || !form.createdByMemberId) {
      return;
    }
    const splits = transactionSplitsForForm(form, exactAmount, currencyCode, source.splits);
    if (!splits) {
      return;
    }
    const recurrenceRule = buildMonthlyRecurrence(form.recurrenceEnabled, form.recurrenceEndDate || undefined);
    if (form.recurrenceEnabled && !recurrenceRule) {
      return;
    }

    const updated: BudgetTransaction = {
      ...source,
      title: form.title.trim(),
      amount,
      type: form.type,
      category: form.category,
      paymentMethod: form.type === "expense" ? form.paymentMethod ?? source.paymentMethod ?? "card" : form.paymentMethod ?? source.paymentMethod,
      createdByMemberId: form.createdByMemberId,
      date: localNoonISOString(form.date) ?? source.date,
      recurrenceRule,
      amountMinorUnits: exactAmount,
      currencyCode,
      splits
    };

    if (syncMode === "cloud" && !queueFinancialMutation(() => buildTransactionGateCMutation(updated, financialMutationUserId))) {
      return;
    }

    setState((current) => ({
      ...current,
      transactions: current.transactions.map((candidate) => candidate.id === id ? updated : candidate)
    }));
    setEditingTransaction(null);
    setSelectedTransaction(null);
    setToastMessage("Transaction saved on this device");
    window.setTimeout(() => setToastMessage(""), 2600);
    if (syncMode === "cloud") {
      void runCloudMutation(() => replayGateCFinancialMutations(financialMutationUserId).then(() => undefined));
    }
  }

  function stopFutureOccurrences(id: string, occurrenceDate: string): boolean {
    const source = state.transactions.find((candidate) => candidate.id === id);
    if (!source || !parseMonthlyRecurrence(source.recurrenceRule)) {
      return false;
    }
    const decision = transactionMutationDecision(source);
    if (!decision.isAllowed) {
      setToastMessage(cloudFinancialWritesReadOnly ? gateCFinancialWritesReadOnlyMessage : decision.readOnlyMessage ?? sharedRecordMutationReadOnlyMessage);
      return false;
    }

    const occurrenceDateKey = localDateKey(new Date(occurrenceDate));
    const until = previousLocalDate(occurrenceDateKey);
    if (!until || until < localDateKey(new Date(source.date))) {
      return false;
    }
    if (!window.confirm(`Stop recurring occurrences from ${formatDateLabel(occurrenceDate)} onward? The series will end on ${formatDateLabel(`${until}T12:00:00`)}.`)) {
      return false;
    }

    const updated: BudgetTransaction = { ...source, recurrenceRule: buildMonthlyRecurrence(true, until) };
    if (syncMode === "cloud" && !queueFinancialMutation(() => buildTransactionGateCMutation(updated, financialMutationUserId))) {
      return false;
    }

    setState((current) => ({
      ...current,
      transactions: current.transactions.map((candidate) => candidate.id === id ? updated : candidate)
    }));
    setSelectedTransaction(null);
    setToastMessage("Recurring series updated");
    window.setTimeout(() => setToastMessage(""), 2600);
    if (syncMode === "cloud") {
      void runCloudMutation(() => replayGateCFinancialMutations(financialMutationUserId).then(() => undefined));
    }
    return true;
  }

  function closeTransactionDialog() {
    setIsAddingTransaction(false);
    window.setTimeout(() => addTransactionButtonRef.current?.focus(), 0);
  }

  function closeEditTransactionDialog() {
    setEditingTransaction(null);
  }

  function deleteTransaction(id: string): boolean {
    const transaction = state.transactions.find((candidate) => candidate.id === id);
    if (!transaction) {
      return false;
    }
    const decision = transactionMutationDecision(transaction);
    if (!decision.isAllowed) {
      setToastMessage(cloudFinancialWritesReadOnly ? gateCFinancialWritesReadOnlyMessage : decision.readOnlyMessage ?? sharedRecordMutationReadOnlyMessage);
      return false;
    }
    if (
      transaction?.recurrenceRule?.startsWith("monthly") &&
      !window.confirm(`Delete "${transaction.title}" and its entire recurring series? This cannot be undone.`)
    ) {
      return false;
    }

    if (syncMode === "cloud" && !queueFinancialMutation(() => buildTransactionDeleteGateCMutation(transaction, financialMutationUserId))) {
      return false;
    }

    setState((current) => ({
      ...current,
      transactions: current.transactions.filter((transaction) => transaction.id !== id)
    }));

    if (syncMode === "cloud") {
      void runCloudMutation(() => replayGateCFinancialMutations(financialMutationUserId).then(() => undefined));
    }
    return true;
  }

  function deleteSettlement(id: string): boolean {
    const settlement = state.settlements.find((candidate) => candidate.id === id);
    if (!settlement) {
      return false;
    }
    const decision = settlementMutationDecision(settlement);
    if (!decision.isAllowed) {
      setToastMessage(cloudFinancialWritesReadOnly ? gateCFinancialWritesReadOnlyMessage : decision.readOnlyMessage ?? sharedRecordMutationReadOnlyMessage);
      return false;
    }
    if (!window.confirm("Delete this settlement record? The associated payment will no longer reduce the household balance.")) {
      return false;
    }

    if (syncMode === "cloud" && !queueFinancialMutation(() => buildSettlementDeleteGateCMutation(settlement, financialMutationUserId))) {
      return false;
    }

    setState((current) => ({
      ...current,
      settlements: current.settlements.filter((candidate) => candidate.id !== id)
    }));
    if (syncMode === "cloud") {
      void runCloudMutation(() => replayGateCFinancialMutations(financialMutationUserId).then(() => undefined), "Settlement deleted");
    }
    return true;
  }

  function settleBalance(suggestion: ReturnType<typeof settlementSuggestions>[number]) {
    const decision = recordCapability(currentBudget.id, "create");
    if (!decision.isAllowed) {
      setToastMessage(cloudFinancialWritesReadOnly ? gateCFinancialWritesReadOnlyMessage : decision.readOnlyMessage ?? sharedRecordMutationReadOnlyMessage);
      return;
    }
    const settlementCurrencyCode = normalizedCurrencyCode(settings.currencyCode);
    const settlementAmountMinorUnits = amountMinorUnits(suggestion.amount, settlementCurrencyCode);
    if (settlementAmountMinorUnits === undefined) {
      setToastMessage("This settlement amount could not be recorded safely.");
      return;
    }
    const settlementAmount = amountFromMinorUnits(settlementAmountMinorUnits, settlementCurrencyCode);
    if (!window.confirm(`Record that ${suggestion.from.displayName} paid ${suggestion.to.displayName} ${formatMoney(settlementAmount, settlementCurrencyCode)}? This records a payment in your household history.`)) {
      return;
    }

    const settlementDate = localNoonISOString(localDateKey()) ?? new Date().toISOString();
    const settlement: Settlement = {
      id: makeId(),
      budgetId: currentBudget.id,
      userId: state.currentUserId,
      createdByUserId: financialMutationUserId,
      fromMemberId: suggestion.from.id,
      toMemberId: suggestion.to.id,
      amount: settlementAmount,
      amountMinorUnits: settlementAmountMinorUnits,
      currencyCode: settlementCurrencyCode,
      date: settlementDate
    };

    if (syncMode === "cloud" && !queueFinancialMutation(() => buildSettlementGateCMutation(settlement, financialMutationUserId))) {
      return;
    }

    setState((current) => ({
      ...current,
      settlements: [...current.settlements, settlement]
    }));
    if (syncMode === "cloud") {
      void runCloudMutation(() => replayGateCFinancialMutations(financialMutationUserId).then(() => undefined), "Settlement saved");
    }
  }

  function addMember(name: string, email: string) {
    if (!householdCapabilities.canManageMembers) {
      setCloudMessage(householdOwnerOnlyMessage);
      return false;
    }

    if (!name.trim()) {
      return false;
    }

    const palette = ["#3B8FE2", "#E2572E", "#1FA37D", "#7B6EE6"];
    const emailValue = email.trim();
    const emailKey = normalizedEmail(emailValue);
    const existingActiveMember = emailKey
      ? budgetMembers.some((member) => normalizedEmail(member.email ?? "") === emailKey && member.inviteStatus === "active")
      : false;

    if (existingActiveMember) {
      setCloudMessage("That email is already an active member of this budget.");
      return false;
    }

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

    return true;
  }

  function handleImport() {
    if (syncModeRef.current === "cloud") {
      setImportError("Cloud imports are disabled because a refresh would replace them. Sign out and use local mode to import a backup.");
      return;
    }
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
        const isAccountTransition = activeUserId.current !== nextSession.user.id;
        activeUserId.current = nextSession.user.id;
        sessionUser.current = nextSession.user;
        syncModeRef.current = "cloud";
        setSession(nextSession);
        setSyncMode("cloud");
        if (isAccountTransition) {
          setVerifiedCloudBudgetIds([]);
        }
        if (isAccountTransition) {
          setState(loadCloudState(nextSession.user.id));
        }
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
      activeUserId.current = null;
      sessionUser.current = null;
      setVerifiedCloudBudgetIds([]);
      const nextSyncMode = modeAfterSignOut(supabaseConfigStatus === "configured");
      syncModeRef.current = nextSyncMode;
      setSession(null);
      setSyncMode(nextSyncMode);
      if (nextSyncMode === "local") {
        setState(loadState(localStateStorageKey));
        setCloudMessage("Local mode is active on this computer.");
      } else {
        setCloudMessage("You are signed out. Sign in to continue, or use this computer for local mode.");
      }
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

  if (authEntryIsVisible(syncMode, !!session, supabaseConfigStatus === "configured") && supabase) {
    return (
      <AuthGate
        errorMessage={cloudError}
        statusMessage={cloudMessage}
        onSubmit={handleAuthSubmit}
        onUseLocal={() => {
          syncModeRef.current = "local";
          setVerifiedCloudBudgetIds([]);
          setState(loadState(localStateStorageKey));
          setSyncMode("local");
          setCloudError("");
          setCloudMessage("Local mode is active on this computer.");
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
        statusText={cloudError ? "Needs attention" : cloudMessage}
      />
      <main className="workspace">
        <header className="topbar">
          <div className="topbar-title">
            <p className="context-label">
              <Home size={13} aria-hidden="true" />
              {currentBudget.name}
            </p>
            <h1>{activeTabTitle[activeTab]}</h1>
          </div>
          <div className="topbar-actions">
            <label className="month-control">
              <CalendarDays size={18} aria-hidden="true" />
              <span>{formatMonthLabel(selectedMonth)}</span>
              <input
                type="month"
                value={selectedMonth}
                onChange={(event) => setSelectedMonth(event.target.value)}
                aria-label="Selected month"
              />
              <ChevronDown size={14} aria-hidden="true" />
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
                {isCloudLoading ? "Syncing…" : "Sync now"}
              </button>
            )}
            {syncMode === "local" && supabase && (
              <button
                className="secondary-action compact"
                onClick={() => {
                  syncModeRef.current = "cloud";
                  setVerifiedCloudBudgetIds([]);
                  setSyncMode("cloud");
                  setCloudMessage("Sign in to sync with Supabase.");
                }}
              >
                <Cloud size={17} aria-hidden="true" />
                Cloud
              </button>
            )}
            <button
              className="primary-action"
              onClick={() => setIsAddingTransaction(true)}
              ref={addTransactionButtonRef}
              type="button"
              disabled={!canCreateFinancialRecord}
              title={!canCreateFinancialRecord ? financialMutationReadOnlyMessage : undefined}
            >
              <Plus size={18} aria-hidden="true" />
              <span className="desktop-action-label">Add transaction</span>
              <span className="mobile-action-label">Add</span>
            </button>
          </div>
        </header>

        {cloudFinancialWritesReadOnly && (
          <div className="rollout-notice" role="status">
            {gateCFinancialWritesReadOnlyMessage} You can still review cloud data and edit non-financial settings.
          </div>
        )}

        {activeTab !== "settings" && budgetMembers.length > 1 && (
          <div className="member-subbar">
            <span>Filter by member</span>
            <MemberFilter members={budgetMembers} selectedMemberId={selectedMemberId} onSelect={setSelectedMemberId} />
          </div>
        )}

        {activeTab === "dashboard" && (
          <DashboardView
            settings={settings}
            totals={totals}
            categoryTotals={categoryTotals}
            settlements={settlements}
            budgetTransactions={budgetTransactions}
            budgetSettlements={budgetSettlements}
            transactions={displayedTransactions}
            selectedMonth={selectedMonth}
            members={budgetMembers}
            onViewAll={() => setActiveTab("transactions")}
            onOpenBudget={() => setActiveTab("budget")}
            onOpenCategory={setSelectedCategory}
            onOpenSettlementHistory={() => setIsSettlementHistoryOpen(true)}
            onSettle={settleBalance}
            onOpenTransaction={setSelectedTransaction}
            canSettle={canCreateFinancialRecord}
            mutationReadOnlyMessage={financialMutationReadOnlyMessage}
          />
        )}

        {activeTab === "transactions" && (
          <TransactionsView
            settings={settings}
            transactions={displayedTransactions}
            members={budgetMembers}
            memberId={memberFilter}
            selectedMonth={selectedMonth}
            search={transactionSearch}
            onSearch={setTransactionSearch}
            onDelete={deleteTransaction}
            onOpenTransaction={setSelectedTransaction}
            onAddTransaction={() => setIsAddingTransaction(true)}
            financialReadOnly={cloudFinancialWritesReadOnly}
            canCreate={canCreateFinancialRecord}
            mutationReadOnlyMessage={financialMutationReadOnlyMessage}
            canDelete={
              (transaction) => transactionMutationDecision(transaction).isAllowed
            }
          />
        )}

        {activeTab === "budget" && (
          <BudgetView
            settings={settings}
            totals={totals}
            transactions={monthTransactions}
            members={budgetMembers}
            memberId={memberFilter}
            selectedMonth={selectedMonth}
            onSettingsChange={updateSettings}
            onOpenCategory={setSelectedCategory}
          />
        )}

        {activeTab === "settings" && (
          <SettingsView
            settings={settings}
            state={state}
            transactions={budgetTransactions}
            members={budgetMembers}
            currentMember={currentBudgetMember}
            capabilities={householdCapabilities}
            currencyChangeAllowed={currencyCanChange}
            currencyChangeMessage={currencyRestrictionMessage}
            importText={importText}
            importError={importError}
            onSettingsChange={updateSettings}
            onUpdateProfileName={updateProfileName}
            onSaveCategory={saveCategory}
            onRemoveCategory={removeCategory}
            onUnhideCategory={unhideCategory}
            onAddMember={addMember}
            onImportTextChange={setImportText}
            onImport={handleImport}
            onReset={() => {
              const resetMessage =
                syncMode === "cloud"
                  ? "Clear this browser's BudgetMate cache and download the latest cloud data? Nothing will be deleted from Supabase."
                  : "Reset all local BudgetMate data on this computer? This cannot be undone.";
              if (window.confirm(resetMessage)) {
                if (syncMode === "cloud" && session?.user) {
                  clearState(activeStorageKey);
                  void reloadCloudState();
                } else {
                  setState(resetState(localStateStorageKey));
                }
              }
            }}
            syncMode={syncMode}
            user={session?.user}
            cloudMessage={cloudMessage}
            cloudError={cloudError}
            isCloudLoading={isCloudLoading}
            pendingInvites={pendingInvites}
            onRefresh={() => void reloadCloudState()}
            onSignOut={() => void handleSignOut()}
            onCreateSharedBudget={(name) => void createSharedBudget(name)}
            onAcceptInvite={(invite) => void acceptInvite(invite)}
            onOpenTransaction={setSelectedTransaction}
          />
        )}
      </main>

      {isAddingTransaction && canCreateFinancialRecord && (
        <TransactionDialog
          members={budgetMembers}
          settings={settings}
          transactions={budgetTransactions}
          defaultMemberId={currentBudgetMember?.id}
          onClose={closeTransactionDialog}
          onSubmit={addTransaction}
        />
      )}
      {selectedCategory && (
        <CategoryTransactionsDialog
          category={selectedCategory}
          selectedMonth={selectedMonth}
          transactions={categoryTransactions}
          settings={settings}
          members={budgetMembers}
          memberId={memberFilter}
          onClose={() => setSelectedCategory(null)}
          onOpenTransaction={(transaction) => {
            setSelectedCategory(null);
            setSelectedTransaction(transaction);
          }}
        />
      )}
      {isSettlementHistoryOpen && (
        <SettlementHistoryDialog
          settlements={budgetSettlements}
          settings={settings}
          members={budgetMembers}
          onClose={() => setIsSettlementHistoryOpen(false)}
          canDelete={(settlement) => settlementMutationDecision(settlement).isAllowed}
          onDelete={deleteSettlement}
        />
      )}
      {selectedTransaction && (
        <TransactionDetailDialog
          transaction={selectedTransaction}
          sourceTransaction={state.transactions.find((candidate) => candidate.id === selectedTransaction.id)}
          settings={settings}
          members={budgetMembers}
          canEdit={transactionMutationDecision(selectedTransaction).isAllowed}
          canDelete={transactionMutationDecision(selectedTransaction).isAllowed}
          mutationReadOnlyMessage={financialMutationReadOnlyMessage}
          onClose={() => setSelectedTransaction(null)}
          onEdit={() => {
            const source = state.transactions.find((candidate) => candidate.id === selectedTransaction.id) ?? selectedTransaction;
            setSelectedTransaction(null);
            setEditingTransaction(source);
          }}
          onDelete={(id) => {
            if (deleteTransaction(id)) {
              setSelectedTransaction(null);
            }
          }}
          onStopFutureOccurrences={stopFutureOccurrences}
        />
      )}
      {editingTransaction && transactionMutationDecision(editingTransaction).isAllowed && (
        <TransactionDialog
          transaction={editingTransaction}
          members={budgetMembers}
          settings={settings}
          transactions={budgetTransactions}
          defaultMemberId={editingTransaction.createdByMemberId}
          onClose={closeEditTransactionDialog}
          onSubmit={(form) => updateTransaction(editingTransaction.id, form)}
        />
      )}
      {toastMessage && (
        <div className="toast" role="status" aria-live="polite">
          <CheckCircle2 size={17} aria-hidden="true" />
          {toastMessage}
        </div>
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

function Sidebar({
  activeTab,
  onTabChange,
  syncMode,
  statusText
}: {
  activeTab: Tab;
  onTabChange: (tab: Tab) => void;
  syncMode: SyncMode;
  statusText: string;
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
        <div className="brand-mark">B</div>
        <div>
          <strong>BudgetMate</strong>
        </div>
      </div>
      <p className="sidebar-label">Menu</p>
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
        <span className={syncMode === "cloud" ? "sync-dot cloud" : "sync-dot local"} aria-hidden="true" />
        <div>
          <strong>{syncMode === "cloud" ? "Cloud sync" : "Local data"}</strong>
          <span>{statusText}</span>
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
  const labelsByMemberId = new Map(memberFilterLabels(members).map((label) => [label.memberId, label]));

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
      {members.map((member) => {
        const label = labelsByMemberId.get(member.id);
        const fullName = label?.fullName ?? member.displayName;
        return (
          <button
            key={member.id}
            className={selectedMemberId === member.id ? "member-chip active" : "member-chip"}
            onClick={() => onSelect(member.id)}
            aria-pressed={selectedMemberId === member.id}
            aria-label={`Filter transactions by ${fullName}`}
            style={{ "--member-color": member.color } as CSSProperties}
            title={fullName}
            type="button"
          >
            <MemberBadge member={member} />
            <span>{label?.displayLabel ?? fullName}</span>
          </button>
        );
      })}
    </div>
  );
}

function DashboardView({
  settings,
  totals,
  categoryTotals,
  settlements,
  budgetTransactions,
  budgetSettlements,
  transactions,
  selectedMonth,
  members,
  onViewAll,
  onOpenBudget,
  onOpenCategory,
  onOpenSettlementHistory,
  onSettle,
  onOpenTransaction,
  canSettle,
  mutationReadOnlyMessage
}: {
  settings: BudgetSettings;
  totals: ReturnType<typeof dashboardTotals>;
  categoryTotals: ReturnType<typeof categoryBreakdown>;
  settlements: ReturnType<typeof settlementSuggestions>;
  budgetTransactions: BudgetTransaction[];
  budgetSettlements: Settlement[];
  transactions: BudgetTransaction[];
  selectedMonth: string;
  members: BudgetMember[];
  onViewAll: () => void;
  onOpenBudget: () => void;
  onOpenCategory: (category: string) => void;
  onOpenSettlementHistory: () => void;
  onSettle: (settlement: ReturnType<typeof settlementSuggestions>[number]) => void;
  onOpenTransaction: (transaction: BudgetTransaction) => void;
  canSettle: boolean;
  mutationReadOnlyMessage: string;
}) {
  const [expandedSettlementId, setExpandedSettlementId] = useState<string | null>(null);
  const budgetLimit = monthlyBudget(settings, selectedMonth);
  const spentRatio = budgetLimit > 0 ? Math.min(1, Math.max(0, totals.totalExpenses / budgetLimit)) : 0;
  const savingsRate = totals.totalIncome > 0
    ? Math.max(0, ((totals.totalIncome - totals.totalExpenses) / totals.totalIncome) * 100)
    : 0;
  const topCategory = categoryTotals[0];
  const topCategoryPercent = topCategory && totals.totalExpenses > 0 ? Math.round((topCategory.amount / totals.totalExpenses) * 100) : 0;
  const insightText = topCategory
    ? `${categoryName(topCategory.category)} is your largest expense this month - ${topCategoryPercent}% of all spending.`
    : "Add expenses to unlock category insights.";

  return (
    <section className="dashboard-grid">
      <div className="kpi-band">
        <div className="balance-panel">
          <p className="eyebrow">{netScopeLabel(selectedMonth)}</p>
          <strong>{formatMoney(totals.currentBalance, settings.currencyCode)}</strong>
          <div className="pacing">
            <div>
              <span>Monthly budget pacing</span>
              <b>{Math.round(spentRatio * 100)}%</b>
            </div>
            <div className="progress-track" aria-hidden="true">
              <span style={{ width: `${spentRatio * 100}%` }} />
            </div>
            <small>
              {formatMoney(totals.totalExpenses, settings.currencyCode)} of {formatMoney(budgetLimit, settings.currencyCode)}
            </small>
          </div>
        </div>

        <SummaryTile
          label="Income"
          amount={totals.totalIncome}
          currencyCode={settings.currencyCode}
          tone="income"
          footnote={`${transactions.filter((transaction) => transaction.type === "income").length} deposit this month`}
        />
        <SummaryTile
          label="Expenses"
          amount={totals.totalExpenses}
          currencyCode={settings.currencyCode}
          tone="expense"
          footnote={`across ${categoryTotals.length} ${categoryTotals.length === 1 ? "category" : "categories"}`}
        />
        <SummaryTile
          label="Savings rate"
          amount={savingsRate}
          currencyCode={settings.currencyCode}
          tone="warning"
          format="percent"
          footnote={savingsRate >= 30 ? "healthy - target 30%" : "target 30%"}
        />
      </div>

      <section className="panel category-panel">
        <div className="panel-heading">
          <h2>Expense breakdown</h2>
          <span>
            {formatMoney(totals.totalExpenses, settings.currencyCode)} · {categoryTotals.length} active
          </span>
        </div>
        <ExpenseBreakdownChart
          items={categoryTotals.slice(0, 5)}
          total={totals.totalExpenses}
          currencyCode={settings.currencyCode}
          onOpenCategory={onOpenCategory}
        />
      </section>

      <section className="panel settlement-panel">
        <div className="panel-heading">
          <h2>Top categories</h2>
          <span>This month</span>
        </div>
        <TopSpendingChart items={categoryTotals.slice(0, 6)} currencyCode={settings.currencyCode} onOpenCategory={onOpenCategory} />
      </section>

      <section className="panel recent-panel">
        <div className="panel-heading">
          <h2>Recent activity</h2>
          <button className="text-action" type="button" onClick={onViewAll}>
            View all
          </button>
        </div>
        <TransactionList
          transactions={transactions.slice(0, 5)}
          settings={settings}
          members={members}
          onOpenTransaction={onOpenTransaction}
        />
      </section>

      <section className="panel settle-panel">
        <div className="panel-heading">
          <h2>Settle up</h2>
          <button className="text-action" type="button" onClick={onOpenSettlementHistory}>
            History{budgetSettlements.length ? ` · ${budgetSettlements.length}` : ""}
          </button>
        </div>
        <div className="settlement-list">
          {settlements.length === 0 ? (
            <div className="empty-state">No open household balances.</div>
          ) : (
            settlements.slice(0, 4).map((settlement) => {
              const explanation = settlementExplanation(
                budgetTransactions,
                budgetSettlements,
                settlement.from.id,
                settlement.to.id
              );
              return (
              <div key={settlement.id} className="settlement-row-wrap">
                <div className="settlement-row">
                <div className="avatar-pair" aria-hidden="true">
                  <MemberBadge member={settlement.from} compact />
                  <MemberBadge member={settlement.to} compact />
                </div>
                <button
                  className="settlement-copy settlement-explanation-trigger"
                  type="button"
                  onClick={() => setExpandedSettlementId((current) => current === settlement.id ? null : settlement.id)}
                  aria-expanded={expandedSettlementId === settlement.id}
                >
                  <strong>
                    {firstName(settlement.from.displayName)} pays {firstName(settlement.to.displayName)}
                  </strong>
                  <span className="settlement-amount">{formatMoney(settlement.amount, settings.currencyCode)}</span>
                </button>
                <button
                  className="ghost-button small settlement-action"
                  type="button"
                  onClick={() => onSettle(settlement)}
                  aria-label={`Settle ${firstName(settlement.from.displayName)} paying ${firstName(settlement.to.displayName)}`}
                  disabled={!canSettle}
                  title={!canSettle ? mutationReadOnlyMessage : undefined}
                >
                  Settle
                </button>
              </div>
                {expandedSettlementId === settlement.id && (
                  <SettlementExplanation
                    explanation={explanation}
                    from={settlement.from}
                    to={settlement.to}
                    currencyCode={settings.currencyCode}
                  />
                )}
              </div>
              );
            })
          )}
        </div>
      </section>

      <section className="insight-panel">
        <div className="insight-icon">
          <Lightbulb size={18} aria-hidden="true" />
        </div>
        <div>
          <strong>{insightText}</strong>
          <span>
            {budgetLimit > 0
              ? `${Math.round(spentRatio * 100)}% of your ${formatMoney(budgetLimit, settings.currencyCode)} monthly budget is used${
                  daysLeftInMonth(selectedMonth) ? ` with ${daysLeftInMonth(selectedMonth)} days left` : ""
                }.`
              : "Set up category budgets to track your pacing."}
          </span>
          {budgetLimit <= 0 && (
            <button className="text-action" type="button" onClick={onOpenBudget}>
              Set up budgets
            </button>
          )}
        </div>
        <em>Spending insight</em>
      </section>
    </section>
  );
}

function SummaryTile({
  label,
  amount,
  currencyCode,
  tone,
  format = "money",
  footnote
}: {
  label: string;
  amount: number;
  currencyCode: string;
  tone: "income" | "expense" | "warning";
  format?: "money" | "percent";
  footnote: string;
}) {
  const displayValue = format === "percent" ? `${amount.toFixed(2)}%` : formatMoney(amount, currencyCode);
  return (
    <section className={`summary-tile ${tone}`} aria-label={`${label}: ${displayValue}`}>
      <span className="metric-label">
        <i aria-hidden="true" />
        {label}
      </span>
      <strong>{displayValue}</strong>
      <small>{footnote}</small>
    </section>
  );
}

function SettlementExplanation({
  explanation,
  from,
  to,
  currencyCode
}: {
  explanation: ReturnType<typeof settlementExplanation>;
  from: BudgetMember;
  to: BudgetMember;
  currencyCode: string;
}) {
  return (
    <div className="settlement-explanation">
      <p>
        {firstName(from.displayName)} owes {firstName(to.displayName)} {formatMoney(explanation.expenseTotal, currencyCode)} in shared expenses.
      </p>
      {explanation.reversedExpenseTotal > 0 && (
        <p>{firstName(to.displayName)} covered {formatMoney(explanation.reversedExpenseTotal, currencyCode)} for {firstName(from.displayName)}.</p>
      )}
      {explanation.paidTotal > 0 && (
        <p>{firstName(from.displayName)} already paid {formatMoney(explanation.paidTotal, currencyCode)} toward this balance.</p>
      )}
      {explanation.receivedTotal > 0 && (
        <p>{firstName(to.displayName)} already paid {formatMoney(explanation.receivedTotal, currencyCode)} back toward this balance.</p>
      )}
      <div className="settlement-explanation-items">
        {explanation.owedExpenses.map((item) => (
          <span key={`owed-${item.id}`}>{item.title} · {formatMoney(item.amount, currencyCode)}</span>
        ))}
        {explanation.priorSettlements.map((settlement) => (
          <span key={settlement.id}>Payment on {formatDateLabel(settlement.date)} · {formatMoney(settlement.amount, settlement.currencyCode ?? currencyCode)}</span>
        ))}
      </div>
      <strong>Net suggested payment: {formatMoney(Math.max(0, explanation.netAmount), currencyCode)}</strong>
    </div>
  );
}

function ExpenseBreakdownChart({
  items,
  total,
  currencyCode,
  onOpenCategory
}: {
  items: ReturnType<typeof categoryBreakdown>;
  total: number;
  currencyCode: string;
  onOpenCategory: (category: string) => void;
}) {
  if (items.length === 0 || total <= 0) {
    return <div className="empty-state">No expenses in this view.</div>;
  }

  return (
    <div className="breakdown-chart" aria-label="Expense breakdown">
      <div className="stacked-bar" aria-hidden="true">
        {items.map((item) => (
          <span
            key={item.category}
            style={{
              "--category-color": categoryColor(item.category),
              width: `${Math.max(3, (item.amount / total) * 100)}%`
            } as CSSProperties}
          />
        ))}
      </div>
      <div className="breakdown-legend">
        {items.map((item) => {
        const percentage = Math.round((item.amount / total) * 100);
        return (
          <button
            key={item.category}
            className="breakdown-row category-drilldown"
            type="button"
            onClick={() => onOpenCategory(item.category)}
            aria-label={`View ${categoryName(item.category)} expenses`}
          >
            <i style={{ backgroundColor: categoryColor(item.category) }} aria-hidden="true" />
            <span>{categoryName(item.category)}</span>
            <em>{percentage}%</em>
            <strong>{formatMoney(item.amount, currencyCode)}</strong>
          </button>
        );
      })}
      </div>
    </div>
  );
}

function TopSpendingChart({
  items,
  currencyCode,
  onOpenCategory
}: {
  items: ReturnType<typeof categoryBreakdown>;
  currencyCode: string;
  onOpenCategory: (category: string) => void;
}) {
  const maxAmount = Math.max(...items.map((item) => item.amount), 0);

  if (items.length === 0 || maxAmount <= 0) {
    return <div className="empty-state">No category spending yet.</div>;
  }

  return (
    <div className="top-spending-chart" aria-label="Top spending categories">
      {items.map((item) => (
        <button
          key={item.category}
          className="spending-bar-row category-drilldown"
          type="button"
          onClick={() => onOpenCategory(item.category)}
          aria-label={`View ${categoryName(item.category)} expenses`}
          style={{ "--category-color": categoryColor(item.category) } as CSSProperties}
        >
          <span>{categoryName(item.category)}</span>
          <div className="spending-track">
            <b style={{ width: `${Math.max(8, (item.amount / maxAmount) * 100)}%` }} />
          </div>
          <strong>{formatMoney(item.amount, currencyCode)}</strong>
        </button>
      ))}
    </div>
  );
}

function TransactionsView({
  settings,
  transactions,
  members,
  memberId,
  selectedMonth,
  search,
  onSearch,
  onDelete,
  onOpenTransaction,
  onAddTransaction,
  financialReadOnly,
  canCreate,
  mutationReadOnlyMessage,
  canDelete
}: {
  settings: BudgetSettings;
  transactions: BudgetTransaction[];
  members: BudgetMember[];
  memberId?: string;
  selectedMonth: string;
  search: string;
  onSearch: (search: string) => void;
  onDelete: (id: string) => void;
  onOpenTransaction: (transaction: BudgetTransaction) => void;
  onAddTransaction: () => void;
  financialReadOnly: boolean;
  canCreate: boolean;
  mutationReadOnlyMessage: string;
  canDelete: (transaction: BudgetTransaction) => boolean;
}) {
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [typeFilter, setTypeFilter] = useState<"all" | TransactionType>("all");
  const memberById = new Map(members.map((member) => [member.id, member]));
  const visibleCategories = useMemo(
    () =>
      [...expenseCategories, ...incomeCategories, ...transactions.map((transaction) => ({
        id: transaction.category,
        name: categoryName(transaction.category)
      }))].filter(
        (category, index, categories) => categories.findIndex((candidate) => candidate.id === category.id) === index
      ),
    [transactions]
  );

  useEffect(() => {
    if (categoryFilter !== "all" && !visibleCategories.some((category) => category.id === categoryFilter)) {
      setCategoryFilter("all");
    }
  }, [categoryFilter, visibleCategories]);

  const filteredTransactions = transactions.filter((transaction) => {
    const query = search.trim().toLowerCase();
    const matchesSearch = `${transaction.title} ${categoryName(transaction.category)}`
      .toLowerCase()
      .includes(query);
    const matchesCategory = categoryFilter === "all" || transaction.category === categoryFilter;
    const matchesType = typeFilter === "all" || transaction.type === typeFilter;
    return matchesSearch && matchesCategory && matchesType;
  });
  const summaryTotals = dashboardTotals(filteredTransactions, monthlyBudget(settings, selectedMonth), memberId);
  const summaryScope = filteredTransactions.length === transactions.length ? "this month" : "this view";
  const hasActiveFilters = search.trim().length > 0 || categoryFilter !== "all" || typeFilter !== "all";

  function clearFilters() {
    onSearch("");
    setCategoryFilter("all");
    setTypeFilter("all");
  }

  return (
    <section className="transactions-view">
      <div className="toolbar">
        <label className="search-control">
          <Search size={17} aria-hidden="true" />
          <input
            value={search}
            onChange={(event) => onSearch(event.target.value)}
            placeholder="Search transactions..."
            aria-label="Search transactions"
          />
        </label>
        <label className="select-control">
          <select value={categoryFilter} onChange={(event) => setCategoryFilter(event.target.value)} aria-label="Filter by category">
            <option value="all">All categories</option>
            {visibleCategories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
          <ChevronDown size={14} aria-hidden="true" />
        </label>
        <label className="select-control">
          <select
            value={typeFilter}
            onChange={(event) => setTypeFilter(event.target.value as "all" | TransactionType)}
            aria-label="Filter by transaction type"
          >
            <option value="all">All types</option>
            <option value="income">Income</option>
            <option value="expense">Expenses</option>
          </select>
          <ChevronDown size={14} aria-hidden="true" />
        </label>
        <span className="toolbar-count">
          {filteredTransactions.length} of {transactions.length}
        </span>
      </div>
      <TransactionSummaryStrip
        totals={summaryTotals}
        currencyCode={settings.currencyCode}
        scopeLabel={summaryScope}
      />
      <div className="panel table-panel">
        {filteredTransactions.length === 0 ? (
          <div className="empty-state">
            <p>{hasActiveFilters ? "No transactions match these filters." : "No transactions this month yet."}</p>
            <button
              className="text-action"
              type="button"
              onClick={hasActiveFilters ? clearFilters : onAddTransaction}
              disabled={!hasActiveFilters && (!canCreate || financialReadOnly)}
              title={!hasActiveFilters && (!canCreate || financialReadOnly) ? mutationReadOnlyMessage : undefined}
            >
              {hasActiveFilters ? "Clear filters" : "Add transaction"}
            </button>
          </div>
        ) : (
          <>
            <div className="transaction-head" aria-hidden="true">
              <span>Transaction</span>
              <span>Member</span>
              <span>Amount</span>
              <span>Date</span>
              <span />
            </div>
            {filteredTransactions.map((transaction) => {
              const member = memberById.get(transaction.createdByMemberId);
              return (
                <article
                  key={transaction.id}
                  className="transaction-row transaction-row-open"
                  role="button"
                  tabIndex={0}
                  aria-label={`Open details for ${transaction.title}`}
                  onClick={() => onOpenTransaction(transaction)}
                  onKeyDown={(event) => activateTransactionOnKeyDown(event, () => onOpenTransaction(transaction))}
                >
                  <div className="transaction-main">
                    <div className={`transaction-icon ${transaction.type}`}>
                      {transaction.type === "income" ? (
                        <ArrowUpCircle size={18} aria-hidden="true" />
                      ) : (
                        <ArrowDownCircle size={18} aria-hidden="true" />
                      )}
                    </div>
                    <div>
                      <strong>{transaction.title}</strong>
                      <span className="category-pill" style={categoryPillStyle(transaction.category)}>
                        {categoryName(transaction.category)}
                      </span>
                    </div>
                  </div>
                  <div className="transaction-member">
                    {member ? <MemberBadge member={member} /> : null}
                    <span>{member?.displayName ?? "Member unavailable"}</span>
                  </div>
                  <div className={`transaction-amount ${transaction.type}`}>
                    <strong>
                      {transaction.type === "expense" ? "-" : "+"}
                      {formatAmountNumber(transaction.amount, settings.currencyCode)}
                    </strong>
                  </div>
                  <time className="transaction-date" dateTime={transaction.date}>
                    {formatDateLabel(transaction.date)}
                  </time>
                  <button
                    className="icon-button subtle"
                    onClick={(event) => {
                      event.stopPropagation();
                      onDelete(transaction.id);
                    }}
                    aria-label={`Delete ${transaction.title}${transaction.recurrenceRule?.startsWith("monthly") ? " recurring series" : ""}`}
                    type="button"
                    disabled={financialReadOnly || !canDelete(transaction)}
                    title={
                      financialReadOnly || !canDelete(transaction)
                        ? mutationReadOnlyMessage
                        : transaction.recurrenceRule?.startsWith("monthly")
                          ? "Delete recurring series"
                          : "Delete transaction"
                    }
                  >
                    <Trash2 size={17} aria-hidden="true" />
                  </button>
                </article>
              );
            })}
          </>
        )}
      </div>
    </section>
  );
}

function TransactionSummaryStrip({
  totals,
  currencyCode,
  scopeLabel
}: {
  totals: ReturnType<typeof dashboardTotals>;
  currencyCode: string;
  scopeLabel: string;
}) {
  return (
    <section className="transaction-summary-strip" aria-label={`Transaction summary for ${scopeLabel}`}>
      <TransactionSummaryMetric
        label="Income"
        value={formatMoney(totals.totalIncome, currencyCode)}
      />
      <TransactionSummaryMetric
        label="Expenses"
        value={formatMoney(totals.totalExpenses, currencyCode)}
      />
      <TransactionSummaryMetric
        label="Net"
        value={formatMoney(totals.currentBalance, currencyCode)}
      />
    </section>
  );
}

function TransactionSummaryMetric({
  label,
  value
}: {
  label: string;
  value: string;
}) {
  return (
    <article className="transaction-summary-metric">
      <strong>{value}</strong>
      <span>{label}</span>
    </article>
  );
}

function BudgetView({
  settings,
  totals,
  transactions,
  members,
  memberId,
  selectedMonth,
  onSettingsChange,
  onOpenCategory
}: {
  settings: BudgetSettings;
  totals: ReturnType<typeof dashboardTotals>;
  transactions: BudgetTransaction[];
  members: BudgetMember[];
  memberId?: string;
  selectedMonth: string;
  onSettingsChange: (settings: BudgetSettings) => void;
  onOpenCategory: (category: string) => void;
}) {
  const spending = categoryBreakdown(transactions, memberId);
  const spendingByCategory = new Map(spending.map((item) => [item.category, item.amount]));
  const memberSpending = memberExpenseTotals(transactions, members);
  const activeCategoryBudgets = selectedCategoryBudgets(settings, selectedMonth);
  const budgetLimit = monthlyBudget(settings, selectedMonth);
  const expenseCategoryOptions = visibleExpenseCategories(settings, transactions);
  const visibleCategoryRows = expenseCategoryOptions.map((category) => {
    const budget = activeCategoryBudgets[category.id] ?? 0;
    const spent = spendingByCategory.get(category.id) ?? 0;
    return { category, budget, spent };
  });
  const { visibleRows, unbudgetedRows } = organizeCategoryBudgetRows(visibleCategoryRows);
  const budgetedCategoryCount = visibleCategoryRows.filter((row) => row.budget > 0).length;
  const maxMemberSpend = Math.max(...memberSpending.map((item) => item.amount), 0);

  function updateCategoryBudget(category: string, value: string) {
    onSettingsChange({
      ...settings,
      categoryBudgets: {
        ...settings.categoryBudgets,
        [monthBudgetKey(selectedMonth, category)]: normalizeAmount(Number(value))
      }
    });
  }

  function renderBudgetRow({ category, spent, budget }: (typeof visibleCategoryRows)[number]) {
    const ratio = budget > 0 ? Math.min(1, spent / budget) : 0;
    const tone = budgetPaceTone(spent, budget);
    return (
      <div key={category.id} className={`budget-row ${tone}`}>
        <button className="budget-category-trigger" type="button" onClick={() => onOpenCategory(category.id)}>
          <strong>
              {settings.categoryEmojis[category.id] ? `${settings.categoryEmojis[category.id]} ` : ""}
              {category.name}
          </strong>
          <span>
              {formatMoney(spent, settings.currencyCode)} of {formatMoney(budget, settings.currencyCode)}
          </span>
          <div className="budget-progress" aria-hidden="true">
            <b style={{ width: `${ratio * 100}%` }} />
          </div>
        </button>
        <label className="budget-input">
          <span>{currencySymbol(settings.currencyCode)}</span>
          <input
            type="number"
            min="0"
            step="10"
            value={activeCategoryBudgets[category.id] ?? 0}
            onChange={(event) => updateCategoryBudget(category.id, event.target.value)}
            aria-label={`${category.name} budget`}
          />
        </label>
      </div>
    );
  }

  return (
    <section className="budget-layout">
      <section className="panel">
        <div className="panel-heading">
          <h2>Category budgets</h2>
          <span>{formatMoney(totals.remainingBudget, settings.currencyCode)} left</span>
        </div>
        <p className="panel-intro">
          {budgetedCategoryCount} of {expenseCategoryOptions.length} categories have a budget for {formatMonthLabel(selectedMonth)}. Category budget changes save automatically.
        </p>
        <div className="budget-list">
          {visibleRows.map(renderBudgetRow)}
        </div>
        {unbudgetedRows.length > 0 && (
          <details className="category-budget-disclosure" key={selectedMonth}>
            <summary>
              <strong>Add category budgets</strong>
              <span>{unbudgetedRows.length} available</span>
            </summary>
            <div className="budget-list">
              {unbudgetedRows.map(renderBudgetRow)}
            </div>
          </details>
        )}
      </section>

      <aside className="budget-rail">
        <section className="budget-summary">
          <p className="eyebrow">Budget summary</p>
          <div>
            <span>Budgeted</span>
            <strong>{formatMoney(budgetLimit, settings.currencyCode)}</strong>
          </div>
          <div>
            <span>Spent</span>
            <strong>{formatMoney(totals.totalExpenses, settings.currencyCode)}</strong>
          </div>
          <hr />
          <div>
            <span>Remaining</span>
            <strong>{formatMoney(totals.remainingBudget, settings.currencyCode)}</strong>
          </div>
        </section>
        <section className="panel member-spending">
          <div className="panel-heading">
            <h2>Member spending</h2>
            <span>{members.length} members</span>
          </div>
          {memberSpending.map(({ member, amount }) => (
            <div key={member.id} className="member-spend-row" style={{ "--member-color": member.color } as CSSProperties}>
              <div>
                <MemberBadge member={member} />
                <strong>{member.displayName}</strong>
                <span>{formatMoney(amount, settings.currencyCode)}</span>
              </div>
              <div className="member-spend-track" aria-hidden="true">
                <b style={{ width: `${maxMemberSpend > 0 ? Math.max(4, (amount / maxMemberSpend) * 100) : 0}%` }} />
              </div>
            </div>
          ))}
        </section>
      </aside>
    </section>
  );
}

function SettingsView({
  settings,
  state,
  transactions,
  members,
  currentMember,
  capabilities,
  currencyChangeAllowed,
  currencyChangeMessage,
  importText,
  importError,
  syncMode,
  user,
  cloudMessage,
  cloudError,
  isCloudLoading,
  pendingInvites,
  onSettingsChange,
  onUpdateProfileName,
  onSaveCategory,
  onRemoveCategory,
  onUnhideCategory,
  onAddMember,
  onImportTextChange,
  onImport,
  onReset,
  onRefresh,
  onSignOut,
  onCreateSharedBudget,
  onAcceptInvite,
  onOpenTransaction
}: {
  settings: BudgetSettings;
  state: AppState;
  transactions: BudgetTransaction[];
  members: BudgetMember[];
  currentMember?: BudgetMember;
  capabilities: HouseholdCapabilities;
  currencyChangeAllowed: boolean;
  currencyChangeMessage: string;
  importText: string;
  importError: string;
  syncMode: SyncMode;
  user?: User;
  cloudMessage: string;
  cloudError: string;
  isCloudLoading: boolean;
  pendingInvites: BudgetInvite[];
  onSettingsChange: (settings: BudgetSettings) => void;
  onUpdateProfileName: (name: string) => string | undefined;
  onSaveCategory: (input: CategorySaveInput) => string | undefined;
  onRemoveCategory: (categoryId: string) => string | undefined;
  onUnhideCategory: (categoryId: string) => void;
  onAddMember: (name: string, email: string) => boolean;
  onImportTextChange: (value: string) => void;
  onImport: () => void;
  onReset: () => void;
  onRefresh: () => void;
  onSignOut: () => void;
  onCreateSharedBudget: (name: string) => void;
  onAcceptInvite: (invite: BudgetInvite) => void;
  onOpenTransaction: (transaction: BudgetTransaction) => void;
}) {
  const [profileName, setProfileName] = useState(currentMember?.displayName ?? "");
  const [profileMessage, setProfileMessage] = useState("");
  const [memberName, setMemberName] = useState("");
  const [memberEmail, setMemberEmail] = useState("");
  const [sharedBudgetName, setSharedBudgetName] = useState("");
  const [memberMessage, setMemberMessage] = useState("");
  const [sharedBudgetMessage, setSharedBudgetMessage] = useState("");
  const [categoryNameInput, setCategoryNameInput] = useState("");
  const [categoryEmojiInput, setCategoryEmojiInput] = useState("");
  const [editingCategoryId, setEditingCategoryId] = useState<string | undefined>();
  const [categoryMessage, setCategoryMessage] = useState("");

  const visibleCategories = visibleExpenseCategories(settings, transactions);
  const hiddenIds = hiddenExpenseCategoryIds(settings);
  const hiddenCategories = expenseCategories.filter((category) => hiddenIds.has(category.id));
  const recurringExpenses = activeRecurringExpenses(transactions);

  useEffect(() => {
    setProfileName(currentMember?.displayName ?? "");
    setProfileMessage("");
  }, [currentMember?.displayName, currentMember?.id]);

  function handleProfileName(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const error = onUpdateProfileName(profileName);
    setProfileMessage(error ?? "Profile name updated.");
  }

  function resetCategoryForm() {
    setCategoryNameInput("");
    setCategoryEmojiInput("");
    setEditingCategoryId(undefined);
  }

  function editCategory(category: { id: string; name: string }) {
    setEditingCategoryId(category.id);
    setCategoryNameInput(category.name);
    setCategoryEmojiInput(settings.categoryEmojis[category.id] ?? "");
    setCategoryMessage("");
  }

  function handleSaveCategory(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const error = onSaveCategory({
      oldCategoryId: editingCategoryId,
      displayName: categoryNameInput,
      emoji: categoryEmojiInput
    });
    if (error) {
      setCategoryMessage(error);
      return;
    }
    setCategoryMessage(editingCategoryId ? "Category updated." : "Category added.");
    resetCategoryForm();
  }

  function handleRemoveCategory(categoryId: string) {
    const category = visibleCategories.find((candidate) => candidate.id === categoryId);
    if (!category || categoryId === "other") {
      return;
    }
    const builtIn = expenseCategories.some((candidate) => candidate.id === categoryId);
    if (!window.confirm(`${builtIn ? "Hide" : "Remove"} ${category.name}? Existing transactions will move to Other.`)) {
      return;
    }
    const error = onRemoveCategory(categoryId);
    setCategoryMessage(error ?? `${category.name} ${builtIn ? "hidden" : "removed"}.`);
  }

  function handleUnhideCategory(categoryId: string) {
    onUnhideCategory(categoryId);
    setCategoryMessage("Category restored.");
  }

  function handleAddMember(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedName = memberName.trim();
    const trimmedEmail = memberEmail.trim();

    if (!trimmedName) {
      setMemberMessage("Enter a member name before adding them.");
      return;
    }

    const didAddMember = onAddMember(trimmedName, trimmedEmail);
    if (!didAddMember) {
      setMemberMessage("That email is already an active member of this budget.");
      return;
    }

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
      setSharedBudgetMessage("Cloud sync is required to create a new household.");
      return;
    }

    if (!trimmedName) {
      setSharedBudgetMessage("Enter a household name before creating it.");
      return;
    }

    onCreateSharedBudget(trimmedName);
    setSharedBudgetName("");
    setSharedBudgetMessage("Creating your new household.");
  }

  const sharedBudgetNote =
    sharedBudgetMessage ||
    (syncMode !== "cloud"
      ? "Sign in to create a new household you will own."
      : sharedBudgetName.trim()
        ? "Ready to create a separate household you will own."
        : "Enter a name to create a separate household.");
  const memberNote =
    memberMessage ||
    (memberName.trim()
      ? memberEmail.trim() && syncMode !== "cloud"
        ? "This member will be added locally until cloud sync is active."
        : "Ready to add this member."
      : syncMode === "cloud"
        ? "Enter a name to add someone. Email is optional."
        : "Enter a name to add someone locally.");
  const currentBudget = state.budgets.find((budget) => budget.id === state.currentBudgetId) ?? state.budgets[0];
  const currencyName = currencyOptions.find((currency) => currency.code === settings.currencyCode)?.name ?? settings.currencyCode;

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
            <span>{syncMode === "cloud" ? (cloudError ? "Needs attention. Try Sync now." : cloudMessage) : "Saved on this device"}</span>
          </div>
          <em className="status-pill">{syncMode === "cloud" ? "Cloud" : "Active"}</em>
        </div>
        <div className="data-actions">
          <button className="ghost-button" onClick={onRefresh} disabled={syncMode !== "cloud" || isCloudLoading}>
            <RefreshCcw size={17} aria-hidden="true" />
            {isCloudLoading ? "Syncing…" : "Sync now"}
          </button>
          <button className="ghost-button" onClick={onSignOut} disabled={syncMode !== "cloud"}>
            <LogOut size={17} aria-hidden="true" />
            Sign out
          </button>
        </div>
        <form className="profile-form" onSubmit={handleProfileName}>
          <label className="field-row vertical">
            <span>Profile name</span>
            <input
              value={profileName}
              onChange={(event) => {
                setProfileName(event.target.value);
                setProfileMessage("");
              }}
              placeholder="Your name"
              disabled={!currentMember}
              aria-describedby="profile-name-note"
            />
          </label>
          <button className="secondary-action" type="submit" disabled={!currentMember || !profileName.trim()}>
            Save name
          </button>
        </form>
        <p className="form-note" id="profile-name-note" role="status" aria-live="polite">
          {profileMessage || (currentMember ? "Only your active profile can be edited." : "Your active profile is unavailable.")}
        </p>
      </section>

      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Preferences</h2>
          <SlidersHorizontal size={18} aria-hidden="true" />
        </div>
        {capabilities.canEditCurrency ? (
          <label className="field-row">
            <span>Currency</span>
            <select
              value={settings.currencyCode}
              disabled={!currencyChangeAllowed}
              aria-describedby="currency-guardrail-note"
              onChange={(event) => onSettingsChange({ ...settings, currencyCode: event.target.value })}
            >
              {currencyOptions.map((currency) => (
                <option key={currency.code} value={currency.code}>
                  {currency.code} - {currency.name}
                </option>
              ))}
            </select>
          </label>
        ) : (
          <div className="field-row" role="group" aria-label="Household currency">
            <span>Currency</span>
            <div>
              <strong>{settings.currencyCode} - {currencyName}</strong>
              <p className="form-note">{householdOwnerOnlyMessage}</p>
            </div>
          </div>
        )}
        {capabilities.canEditCurrency && (
          <p className="form-note" id="currency-guardrail-note" role="status" aria-live="polite">
            {currencyChangeMessage}
          </p>
        )}
        <label className="field-row">
          <span>Appearance</span>
          <select
            value={settings.appearance}
            onChange={(event) => onSettingsChange({ ...settings, appearance: event.target.value as BudgetSettings["appearance"] })}
          >
            <option value="system">System</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </label>
        <div className="status-row compact-status">
          <RefreshCcw size={18} aria-hidden="true" />
          <div>
            <strong>Cloud backup</strong>
            <span>
                {syncMode === "cloud"
                  ? cloudError ? "Needs attention. Try Sync now." : cloudMessage
                : supabaseConfigStatus === "configured"
                  ? "Supabase configured"
                  : "Ready for Supabase config"}
            </span>
          </div>
          <span className={syncMode === "cloud" ? "switch is-on" : "switch"} aria-hidden="true">
            <i />
          </span>
        </div>
      </section>

      <section className="panel settings-panel category-settings-panel">
        <div className="panel-heading">
          <h2>Categories</h2>
          <span>{visibleCategories.length} visible</span>
        </div>
        <p className="panel-intro">Manage expense categories used by your budget and transactions.</p>
        <div className="category-list">
          {visibleCategories.map((category) => {
            const isBuiltIn = expenseCategories.some((candidate) => candidate.id === category.id);
            const isProtected = category.id === "other";
            return (
              <div key={category.id} className="category-management-row">
                <span className="category-management-emoji" aria-hidden="true">
                  {settings.categoryEmojis[category.id] ?? "•"}
                </span>
                <div>
                  <strong>{category.name}</strong>
                  <span>{isBuiltIn ? "Built-in" : "Custom"}</span>
                </div>
                <div className="category-management-actions">
                  <button className="ghost-button small" type="button" onClick={() => editCategory(category)}>
                    Edit
                  </button>
                  <button
                    className="ghost-button small"
                    type="button"
                    disabled={isProtected}
                    title={isProtected ? "Other is protected" : undefined}
                    onClick={() => handleRemoveCategory(category.id)}
                  >
                    {isBuiltIn ? "Hide" : "Remove"}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
        {hiddenCategories.length > 0 && (
          <div className="category-hidden-list">
            <p className="form-note">Hidden built-in categories</p>
            {hiddenCategories.map((category) => (
              <div key={category.id} className="category-management-row">
                <span className="category-management-emoji muted-emoji" aria-hidden="true">•</span>
                <div>
                  <strong>{category.name}</strong>
                  <span>Hidden built-in</span>
                </div>
                <button className="ghost-button small" type="button" onClick={() => handleUnhideCategory(category.id)}>
                  Unhide
                </button>
              </div>
            ))}
          </div>
        )}
        <form className="member-form category-form" onSubmit={handleSaveCategory}>
          <input
            value={categoryNameInput}
            onChange={(event) => {
              setCategoryNameInput(event.target.value);
              setCategoryMessage("");
            }}
            placeholder="Category name"
            aria-label="Category name"
            disabled={editingCategoryId === "other"}
          />
          <input
            value={categoryEmojiInput}
            onChange={(event) => {
              setCategoryEmojiInput(event.target.value);
              setCategoryMessage("");
            }}
            placeholder="Optional emoji"
            aria-label="Optional category emoji"
            maxLength={12}
          />
          <button className="secondary-action" type="submit" disabled={!categoryNameInput.trim()}>
            <Plus size={17} aria-hidden="true" />
            {editingCategoryId ? "Save category" : "Add category"}
          </button>
          {editingCategoryId && (
            <button className="ghost-button" type="button" onClick={resetCategoryForm}>
              Cancel
            </button>
          )}
        </form>
        <p className="form-note" role="status" aria-live="polite">
          {categoryMessage || "Use a display name. An optional icon must be one emoji."}
        </p>
      </section>

      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Households</h2>
          <span>{state.budgets.length} active</span>
        </div>
        <div className="member-list">
          {state.budgets.map((budget) => {
            const memberCount = state.members.filter((member) => member.budgetId === budget.id).length;
            return (
              <div key={budget.id} className="member-row">
                <span className="household-mark">
                  <Home size={16} aria-hidden="true" />
                </span>
                <div>
                  <strong>{budget.name}</strong>
                  <span>{budget.id === state.currentUserId ? "Personal" : `Shared · ${memberCount} members`}</span>
                </div>
                {currentBudget?.id === budget.id && <em className="status-pill">Current</em>}
              </div>
            );
          })}
        </div>
        <p className="panel-intro">
          Create a separate household that you will own. This does not add a member to the current household.
        </p>
        <form className="member-form household-form" onSubmit={handleCreateSharedBudget}>
          <input
            value={sharedBudgetName}
            onChange={(event) => {
              setSharedBudgetName(event.target.value);
              setSharedBudgetMessage("");
            }}
            placeholder="New household name"
            aria-label="New household name"
            aria-describedby="shared-budget-note"
          />
          <button className="secondary-action" type="submit" disabled={syncMode !== "cloud" || !sharedBudgetName.trim()}>
            <Plus size={17} aria-hidden="true" />
            Create household
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
                <span>{member.email ?? member.role}</span>
              </div>
              <em className="status-pill">{member.inviteStatus}</em>
            </div>
          ))}
        </div>
        {capabilities.canManageMembers ? (
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
              Add member
            </button>
          </form>
        ) : (
          <p className="form-note" id="member-permission-note">
            {householdOwnerOnlyMessage}
          </p>
        )}
        {capabilities.canManageMembers && (
          <p className="form-note" id="member-form-note" role="status" aria-live="polite">
            {memberNote}
          </p>
        )}
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

      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Recurring expenses</h2>
          <RefreshCcw size={18} aria-hidden="true" />
        </div>
        {recurringExpenses.length === 0 ? (
          <div className="empty-state">No recurring expenses right now.</div>
        ) : (
          <div className="recurring-expense-list">
            {recurringExpenses.map((transaction) => {
              const recurrence = parseMonthlyRecurrence(transaction.recurrenceRule);
              const currencyCode = transaction.currencyCode ?? settings.currencyCode;
              return (
                <button
                  key={transaction.id}
                  className="recurring-expense-row"
                  type="button"
                  onClick={() => onOpenTransaction(transaction)}
                >
                  <span className="recurring-expense-icon" aria-hidden="true">
                    <RefreshCcw size={16} />
                  </span>
                  <span className="recurring-expense-copy">
                    <strong>{transaction.title}</strong>
                    <span>{formatMoney(transaction.amount, currencyCode)} · {categoryName(transaction.category)}</span>
                    <small>
                      Started {formatDateLabel(transaction.date)} · {recurrence?.until ? `Stops ${formatDateLabel(`${recurrence.until}T12:00:00`)}` : "No stop date"}
                    </small>
                  </span>
                </button>
              );
            })}
          </div>
        )}
      </section>

      <section className="panel settings-panel">
        <div className="panel-heading">
          <h2>Privacy &amp; support</h2>
          <span>Help</span>
        </div>
        <div className="support-links">
          <a href="https://budgetmate.pages.dev/privacy.html" target="_blank" rel="noreferrer">
            Privacy policy
          </a>
          <a href="https://budgetmate.pages.dev/support.html" target="_blank" rel="noreferrer">
            Support
          </a>
        </div>
      </section>

      <section className="panel settings-panel data-panel">
        <div className="panel-heading">
          <h2>Data</h2>
          <span>{syncMode === "cloud" ? "Cached" : "Stored locally"}</span>
        </div>
        <details className="advanced-data-tools">
          <summary>
            <strong>Advanced data tools</strong>
            <span>Export, import, and cache controls</span>
          </summary>
          <p className="panel-intro">
            {syncMode === "cloud"
              ? "Export the current cache or clear it to download a fresh cloud copy. Import is available in local mode only."
              : "Export a backup, import from another device, or reset everything on this device."}
          </p>
          <div className="data-tools">
            <textarea readOnly value={exportState(state)} aria-label="Exported BudgetMate data" />
            <div className="data-tool-actions">
              <a
                className="primary-action"
                href={`data:application/json;charset=utf-8,${encodeURIComponent(exportState(state))}`}
                download="budgetmate-web-data.json"
              >
                <Download size={17} aria-hidden="true" />
                Export
              </a>
              <textarea
                value={importText}
                onChange={(event) => onImportTextChange(event.target.value)}
                placeholder={syncMode === "cloud" ? "Sign out and use local mode to import" : "Paste exported data"}
                aria-label="Import BudgetMate data"
                disabled={syncMode === "cloud"}
              />
              {importError && <p className="form-error" role="alert">{importError}</p>}
              <button className="ghost-button" onClick={onImport} disabled={syncMode === "cloud"}>
                <Upload size={17} aria-hidden="true" />
                Import
              </button>
            </div>
          </div>
          <div className="danger-zone">
            <div>
              <strong>{syncMode === "cloud" ? "Clear browser cache" : "Reset all local data"}</strong>
              <span>
                {syncMode === "cloud"
                  ? "Removes this browser's cached copy, then downloads the latest data from Supabase."
                  : "Permanently deletes every local transaction, budget, and member on this device."}
              </span>
            </div>
            <button className="danger-action" onClick={onReset}>
              {syncMode === "cloud" ? "Clear cache" : "Reset"}
            </button>
          </div>
        </details>
      </section>
    </section>
  );
}

function TransactionDialog({
  transaction,
  members,
  settings,
  transactions,
  defaultMemberId,
  onClose,
  onSubmit
}: {
  transaction?: BudgetTransaction;
  members: BudgetMember[];
  settings: BudgetSettings;
  transactions: BudgetTransaction[];
  defaultMemberId?: string;
  onClose: () => void;
  onSubmit: (form: TransactionFormState) => void;
}) {
  const resolvedDefaultMemberId = defaultMemberId ?? transaction?.createdByMemberId ?? members[0]?.id ?? "";
  const recurrence = parseMonthlyRecurrence(transaction?.recurrenceRule);
  const expenseCategoryOptions = visibleExpenseCategories(settings, transactions);
  const defaultExpenseCategory = expenseCategoryOptions.some((category) => category.id === "groceries")
    ? "groceries"
    : expenseCategoryOptions[0]?.id ?? "other";
  const effectiveCurrencyCode = transaction?.currencyCode ?? settings.currencyCode;
  const [form, setForm] = useState<TransactionFormState>(() => ({
    type: transaction?.type ?? "expense",
    title: transaction?.title ?? "",
    amount: transaction ? String(transaction.amount) : "",
    category: transaction?.category ?? defaultExpenseCategory,
    paymentMethod: transaction?.paymentMethod,
    createdByMemberId: transaction?.createdByMemberId ?? resolvedDefaultMemberId,
    date: transaction ? localDateKey(new Date(transaction.date)) : todayInputValue(),
    splitEnabled: transaction?.type === "expense" && transaction.splits.length > 0,
    splitMethod: transaction?.splits.length ? "custom" : "equal",
    splitMemberIds: transaction?.splits.map((split) => split.memberId) ?? [],
    splitAmounts: Object.fromEntries(
      transaction?.splits.map((split) => [split.memberId, String(split.amount)]) ?? []
    ),
    recurrenceEnabled: !!recurrence,
    recurrenceEndDate: recurrence?.until ?? ""
  }));
  const [formError, setFormError] = useState("");
  const dialogRef = useRef<HTMLFormElement | null>(null);
  const amountRef = useRef<HTMLInputElement | null>(null);
  const titleRef = useRef<HTMLInputElement | null>(null);
  const memberChoiceChangedRef = useRef(false);

  const categories = form.type === "income" ? incomeCategories : expenseCategoryOptions;
  const formAmountMinorUnits = amountMinorUnits(form.amount, effectiveCurrencyCode);
  const activeMembers = members.filter((member) => member.inviteStatus === "active");
  const splitMembers = members.filter(
    (member) => member.inviteStatus === "active" || form.splitMemberIds.includes(member.id)
  );
  const customSplitValidation =
    form.type === "expense" && form.splitEnabled && form.splitMethod === "custom"
      ? validateCustomSplitAmounts(formAmountMinorUnits, form.splitMemberIds, form.splitAmounts, effectiveCurrencyCode)
      : undefined;
  const equalAllocations =
    form.type === "expense" && form.splitEnabled && formAmountMinorUnits !== undefined
      ? allocateEqualSplitMinorUnits(formAmountMinorUnits, form.splitMemberIds, form.createdByMemberId)
      : undefined;
  const splitValidationMessage =
    form.type !== "expense" || !form.splitEnabled
      ? ""
      : form.splitMemberIds.length === 0
        ? "Select at least one member."
        : formAmountMinorUnits === undefined
          ? "Enter a valid amount to split."
          : form.splitMethod === "equal" && !equalAllocations
            ? "Amount too small for selected members."
          : customSplitValidation?.status === "invalid"
            ? "Enter valid split amounts."
            : customSplitValidation?.status === "under"
              ? `Add ${formatMoney(amountFromMinorUnits(customSplitValidation.differenceMinorUnits ?? 0, effectiveCurrencyCode), effectiveCurrencyCode)} to match the total.`
              : customSplitValidation?.status === "over"
                ? `${formatMoney(amountFromMinorUnits(customSplitValidation.differenceMinorUnits ?? 0, effectiveCurrencyCode), effectiveCurrencyCode)} over the total.`
                : "";
  useEffect(() => {
    if (!categories.some((category) => category.id === form.category)) {
      setForm((current) => ({ ...current, category: categories[0]?.id ?? "other" }));
    }
  }, [categories, form.category]);

  useEffect(() => {
    const currentMemberStillExists = members.some((member) => member.id === form.createdByMemberId);
    if (memberChoiceChangedRef.current && currentMemberStillExists) {
      return;
    }
    if (currentMemberStillExists && form.createdByMemberId === resolvedDefaultMemberId) {
      return;
    }
    updateForm({ createdByMemberId: resolvedDefaultMemberId });
  }, [form.createdByMemberId, members, resolvedDefaultMemberId]);

  useEffect(() => {
    const focusId = window.requestAnimationFrame(() => amountRef.current?.focus());
    return () => window.cancelAnimationFrame(focusId);
  }, []);

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
        next.category = patch.type === "income" ? "work" : defaultExpenseCategory;
        next.splitEnabled = false;
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
    if (formAmountMinorUnits === undefined) {
      setFormError("Enter a valid amount for this currency.");
      return;
    }
    if (!form.date || !form.createdByMemberId) {
      setFormError("Choose a date and member before saving.");
      return;
    }
    const recurrenceRule = buildMonthlyRecurrence(form.recurrenceEnabled, form.recurrenceEndDate || undefined);
    if (form.recurrenceEnabled && !recurrenceRule) {
      setFormError("Enter a valid recurrence end date.");
      return;
    }
    if (form.recurrenceEnabled && form.recurrenceEndDate && form.recurrenceEndDate < form.date) {
      setFormError("Recurrence end date cannot be before the transaction date.");
      return;
    }
    if (splitValidationMessage) {
      setFormError(splitValidationMessage);
      return;
    }

    setFormError("");
    onSubmit(form);
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <form
        className={`dialog ${form.type}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="transaction-dialog-title"
        onMouseDown={(event) => event.stopPropagation()}
        onSubmit={handleSubmit}
        noValidate
        ref={dialogRef}
      >
        <div className="dialog-header">
          <h2 id="transaction-dialog-title">{transaction ? "Edit transaction" : "Add transaction"}</h2>
          <button className="icon-button" onClick={onClose} title="Close" aria-label={`Close ${transaction ? "edit" : "add"} transaction`} type="button">
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

        <label className="amount-hero">
          <span>Amount</span>
          <div>
            <b>{currencySymbol(effectiveCurrencyCode)}</b>
            <input
              type="number"
              min="0"
              step="0.01"
              value={form.amount}
              onChange={(event) => updateForm({ amount: event.target.value })}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                  titleRef.current?.focus();
                }
              }}
              placeholder="0.00"
              ref={amountRef}
              required
              aria-label="Transaction amount"
              aria-invalid={!!formError && (normalizeAmount(Number(form.amount)) <= 0 || formAmountMinorUnits === undefined)}
              aria-describedby={formError ? "transaction-form-error" : undefined}
            />
          </div>
        </label>

        <label className="field-row vertical">
          <span>Title</span>
          <input
            value={form.title}
            onChange={(event) => updateForm({ title: event.target.value })}
            placeholder="What was this for?"
            ref={titleRef}
            required
            aria-invalid={!!formError && !form.title.trim()}
            aria-describedby={formError ? "transaction-form-error" : undefined}
          />
        </label>

        <div className="form-grid">
          <label className="field-row vertical">
            <span>Date</span>
            <input type="date" value={form.date} onChange={(event) => updateForm({ date: event.target.value })} required />
          </label>
          <label className="field-row vertical">
            <span>Category</span>
            <select value={form.category} onChange={(event) => updateForm({ category: event.target.value })} required>
              {categories.map((category) => (
                <option key={category.id} value={category.id}>
                  {settings.categoryEmojis[category.id] ? `${settings.categoryEmojis[category.id]} ` : ""}
                  {category.name}
                </option>
              ))}
            </select>
          </label>
        </div>

        {form.type === "expense" && (
          <label className="field-row vertical">
            <span>Payment method</span>
            <select
              value={form.paymentMethod ?? "card"}
              onChange={(event) => updateForm({ paymentMethod: event.target.value as "cash" | "card" | "paypal" })}
            >
              <option value="cash">Cash</option>
              <option value="card">Card</option>
              <option value="paypal">PayPal</option>
            </select>
          </label>
        )}

        <label className="field-row vertical">
          <span>{form.type === "income" ? "Income for" : "Paid by"}</span>
          <select
            value={form.createdByMemberId}
            onChange={(event) => {
              memberChoiceChangedRef.current = true;
              updateForm({ createdByMemberId: event.target.value });
            }}
            required
          >
            {members.map((member) => (
              <option key={member.id} value={member.id}>
                {member.displayName}
              </option>
            ))}
          </select>
        </label>

        <label className="toggle-row">
          <input
            type="checkbox"
            checked={form.recurrenceEnabled}
            onChange={(event) => updateForm({ recurrenceEnabled: event.target.checked })}
          />
          <span>
            <strong>Repeat monthly</strong>
            <small>{form.recurrenceEnabled ? "Create this transaction on the same day each month." : "This transaction happens once."}</small>
          </span>
        </label>

        {form.recurrenceEnabled && (
          <label className="field-row vertical">
            <span>End date (optional)</span>
            <input
              type="date"
              value={form.recurrenceEndDate}
              min={form.date}
              onChange={(event) => updateForm({ recurrenceEndDate: event.target.value })}
            />
          </label>
        )}

        {form.type === "expense" && activeMembers.length > 0 && (
          <>
            <label className="toggle-row">
              <input
                type="checkbox"
                checked={form.splitEnabled}
                onChange={(event) => updateForm({ splitEnabled: event.target.checked })}
              />
              <span>
                <strong>Split this expense</strong>
                <small>{form.splitEnabled ? "Choose participants and allocation." : "Share this expense with household members."}</small>
              </span>
            </label>

            {form.splitEnabled && (
              <section className="split-editor" aria-label="Expense split editor">
                <div className="segmented split-method" role="group" aria-label="Split method">
                  <button
                    className={form.splitMethod === "equal" ? "active" : ""}
                    onClick={() => updateForm({ splitMethod: "equal" })}
                    aria-pressed={form.splitMethod === "equal"}
                    type="button"
                  >
                    Equal
                  </button>
                  <button
                    className={form.splitMethod === "custom" ? "active" : ""}
                    onClick={() => updateForm({ splitMethod: "custom" })}
                    aria-pressed={form.splitMethod === "custom"}
                    type="button"
                  >
                    Custom
                  </button>
                </div>

                <div className="split-editor-list">
                  {splitMembers.map((member) => {
                    const selected = form.splitMemberIds.includes(member.id);
                    const equalShare = equalAllocations?.find((allocation) => allocation.memberId === member.id);
                    return (
                      <div key={member.id} className="split-editor-row">
                        <label className="split-member-choice">
                          <input
                            type="checkbox"
                            checked={selected}
                            disabled={member.inviteStatus !== "active"}
                            onChange={(event) => updateForm({
                              splitMemberIds: event.target.checked
                                ? [...form.splitMemberIds, member.id]
                                : form.splitMemberIds.filter((id) => id !== member.id)
                            })}
                          />
                          <MemberBadge member={member} />
                          <span>{member.displayName}{member.id === form.createdByMemberId ? " (paid)" : ""}</span>
                        </label>
                        {selected && form.splitMethod === "equal" && equalShare && (
                          <strong>{formatMoney(amountFromMinorUnits(equalShare.amountMinorUnits, effectiveCurrencyCode), effectiveCurrencyCode)}</strong>
                        )}
                        {selected && form.splitMethod === "custom" && (
                          <input
                            className="split-amount-input"
                            type="number"
                            min="0"
                            step={normalizedCurrencyCode(effectiveCurrencyCode) === "JPY" ? "1" : "0.01"}
                            value={form.splitAmounts[member.id] ?? ""}
                            onChange={(event) => updateForm({
                              splitAmounts: { ...form.splitAmounts, [member.id]: event.target.value }
                            })}
                            placeholder={formatAmountNumber(0, effectiveCurrencyCode)}
                            aria-label={`Amount for ${member.displayName}`}
                            aria-invalid={customSplitValidation?.status === "invalid"}
                          />
                        )}
                      </div>
                    );
                  })}
                </div>
                {splitValidationMessage && (
                  <p className="form-error" id="split-validation-error" role="alert">
                    {splitValidationMessage}
                  </p>
                )}
              </section>
            )}
          </>
        )}

        {formError && (
          <p className="form-error" id="transaction-form-error" role="alert">
            {formError}
          </p>
        )}

        <div className="dialog-actions">
          <button className="ghost-button" onClick={onClose} type="button">
            Cancel
          </button>
          <button className="primary-action full" type="submit" disabled={!!splitValidationMessage}>
            {transaction ? <CheckCircle2 size={18} aria-hidden="true" /> : <Plus size={18} aria-hidden="true" />}
            {transaction ? "Save changes" : "Add transaction"}
          </button>
        </div>
      </form>
    </div>
  );
}

function CategoryTransactionsDialog({
  category,
  selectedMonth,
  transactions,
  settings,
  members,
  memberId,
  onClose,
  onOpenTransaction
}: {
  category: string;
  selectedMonth: string;
  transactions: BudgetTransaction[];
  settings: BudgetSettings;
  members: BudgetMember[];
  memberId?: string;
  onClose: () => void;
  onOpenTransaction: (transaction: BudgetTransaction) => void;
}) {
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeRef = useRef<HTMLButtonElement | null>(null);
  const total = categoryBreakdown(transactions, memberId).find((item) => item.category === category)?.amount ?? 0;

  useEffect(() => {
    const focusId = window.requestAnimationFrame(() => closeRef.current?.focus());
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
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.cancelAnimationFrame(focusId);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose]);

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <div
        className="dialog category-transactions-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="category-transactions-title"
        ref={dialogRef}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="dialog-header">
          <div>
            <p className="eyebrow">Category expenses</p>
            <h2 id="category-transactions-title">{categoryName(category)}</h2>
          </div>
          <button ref={closeRef} className="icon-button" onClick={onClose} title="Close" aria-label="Close category expenses" type="button">
            <X size={18} aria-hidden="true" />
          </button>
        </div>
        <div className="category-detail-summary">
          <span>{formatMonthLabel(selectedMonth)}</span>
          <strong>{formatMoney(total, settings.currencyCode)}</strong>
          <small>{transactions.length} {transactions.length === 1 ? "expense" : "expenses"}</small>
        </div>
        {transactions.length === 0 ? (
          <div className="empty-state">No {categoryName(category).toLowerCase()} expenses in this view.</div>
        ) : (
          <TransactionList
            transactions={transactions}
            settings={settings}
            members={members}
            onOpenTransaction={onOpenTransaction}
          />
        )}
        <div className="dialog-actions">
          <button className="ghost-button" onClick={onClose} type="button">Close</button>
        </div>
      </div>
    </div>
  );
}

function SettlementHistoryDialog({
  settlements,
  settings,
  members,
  canDelete,
  onClose,
  onDelete
}: {
  settlements: Settlement[];
  settings: BudgetSettings;
  members: BudgetMember[];
  canDelete: (settlement: Settlement) => boolean;
  onClose: () => void;
  onDelete: (id: string) => boolean;
}) {
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeRef = useRef<HTMLButtonElement | null>(null);
  const memberById = new Map(members.map((member) => [member.id, member]));
  const sortedSettlements = [...settlements].sort((left, right) => new Date(right.date).getTime() - new Date(left.date).getTime());

  useEffect(() => {
    const focusId = window.requestAnimationFrame(() => closeRef.current?.focus());
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
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.cancelAnimationFrame(focusId);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose]);

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <div
        className="dialog settlement-history-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="settlement-history-title"
        ref={dialogRef}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="dialog-header">
          <div>
            <p className="eyebrow">Active budget</p>
            <h2 id="settlement-history-title">Settlement history</h2>
          </div>
          <button ref={closeRef} className="icon-button" onClick={onClose} title="Close" aria-label="Close settlement history" type="button">
            <X size={18} aria-hidden="true" />
          </button>
        </div>
        {sortedSettlements.length === 0 ? (
          <div className="empty-state">No settlement payments recorded yet.</div>
        ) : (
          <div className="settlement-history-list">
            {sortedSettlements.map((settlement) => {
              const from = memberById.get(settlement.fromMemberId)?.displayName ?? "Member unavailable";
              const to = memberById.get(settlement.toMemberId)?.displayName ?? "Member unavailable";
              const creatorId = settlement.createdByUserId ?? settlement.userId;
              const creator = members.find((member) => member.authUserId === creatorId || member.id === creatorId)?.displayName ?? creatorId;
              const deletable = canDelete(settlement);
              const currencyCode = settlement.currencyCode ?? settings.currencyCode;
              return (
                <article key={settlement.id} className="settlement-history-row">
                  <dl className="settlement-history-detail">
                    <div><dt>From</dt><dd>{from}</dd></div>
                    <div><dt>To</dt><dd>{to}</dd></div>
                    <div><dt>Amount</dt><dd>{formatMoney(settlement.amount, currencyCode)}</dd></div>
                    <div><dt>Date</dt><dd>{formatDateLabel(settlement.date)}</dd></div>
                    <div><dt>Creator</dt><dd>{creator}</dd></div>
                    <div><dt>Status</dt><dd>{deletable ? "Editable by you" : "Read-only"}</dd></div>
                  </dl>
                  <button
                    className="danger-action settlement-delete-action"
                    type="button"
                    onClick={() => onDelete(settlement.id)}
                    disabled={!deletable}
                    title={deletable ? "Delete settlement" : "This settlement is read-only"}
                  >
                    <Trash2 size={16} aria-hidden="true" />
                    Delete
                  </button>
                </article>
              );
            })}
          </div>
        )}
        <div className="dialog-actions">
          <button className="ghost-button" onClick={onClose} type="button">Close</button>
        </div>
      </div>
    </div>
  );
}

function TransactionDetailDialog({
  transaction,
  sourceTransaction,
  settings,
  members,
  canEdit,
  canDelete,
  mutationReadOnlyMessage,
  onClose,
  onEdit,
  onDelete,
  onStopFutureOccurrences
}: {
  transaction: BudgetTransaction;
  sourceTransaction?: BudgetTransaction;
  settings: BudgetSettings;
  members: BudgetMember[];
  canEdit: boolean;
  canDelete: boolean;
  mutationReadOnlyMessage: string;
  onClose: () => void;
  onEdit: () => void;
  onDelete: (id: string) => void;
  onStopFutureOccurrences: (id: string, occurrenceDate: string) => void;
}) {
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeRef = useRef<HTMLButtonElement | null>(null);
  const currencyCode = transaction.currencyCode ?? settings.currencyCode;
  const memberById = new Map(members.map((member) => [member.id, member]));
  const payer = memberById.get(transaction.createdByMemberId)?.displayName ?? "Member unavailable";
  const creator = transaction.createdByUserId
    ? members.find((member) => member.authUserId === transaction.createdByUserId || member.id === transaction.createdByUserId)?.displayName ?? transaction.createdByUserId
    : undefined;
  const recurrence = recurrenceSummary(transaction.recurrenceRule);
  const isOccurrence = !!sourceTransaction && sourceTransaction.date !== transaction.date;
  const isRecurring = !!parseMonthlyRecurrence(transaction.recurrenceRule);

  useEffect(() => {
    const focusId = window.requestAnimationFrame(() => closeRef.current?.focus());
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
    return () => {
      window.cancelAnimationFrame(focusId);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose]);

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <div
        className="dialog transaction-detail"
        role="dialog"
        aria-modal="true"
        aria-labelledby="transaction-detail-title"
        ref={dialogRef}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="dialog-header">
          <div>
            <p className="eyebrow">Transaction details</p>
            <h2 id="transaction-detail-title">{transaction.title}</h2>
          </div>
          <button ref={closeRef} className="icon-button" onClick={onClose} title="Close" aria-label="Close transaction details" type="button">
            <X size={18} aria-hidden="true" />
          </button>
        </div>

        <div className={`transaction-detail-amount ${transaction.type}`}>
          <strong>{transaction.type === "expense" ? "−" : "+"}{formatMoney(transaction.amount, currencyCode)}</strong>
          <span>{transaction.type === "expense" ? "Expense" : "Income"}</span>
        </div>

        <dl className="transaction-detail-grid">
          <div><dt>Category</dt><dd>{categoryName(transaction.category)}</dd></div>
          <div><dt>Date</dt><dd>{formatDateLabel(transaction.date)}</dd></div>
          <div><dt>{transaction.type === "expense" ? "Paid by" : "Income for"}</dt><dd>{payer}</dd></div>
          <div><dt>Payment method</dt><dd>{transaction.paymentMethod ? transaction.paymentMethod === "paypal" ? "PayPal" : transaction.paymentMethod === "cash" ? "Cash" : "Card" : "Not specified"}</dd></div>
          <div><dt>Recurrence</dt><dd>{recurrence}</dd></div>
          {creator && <div><dt>Creator</dt><dd>{creator}</dd></div>}
        </dl>

        {isOccurrence && (
          <p className="form-note" role="status">
            This is a recurring occurrence. Editing updates the saved source transaction.
          </p>
        )}

        <section className="transaction-splits" aria-labelledby="transaction-splits-title">
          <h3 id="transaction-splits-title">Split participants</h3>
          {transaction.splits.length === 0 ? (
            <p className="form-note">Not split with the household.</p>
          ) : (
            <div className="split-list">
              {transaction.splits.map((split) => (
                <div key={split.id} className="split-row">
                  <span>{memberById.get(split.memberId)?.displayName ?? "Member unavailable"}</span>
                  <strong>{formatMoney(split.amount, currencyCode)}</strong>
                </div>
              ))}
            </div>
          )}
        </section>

        {!canEdit && <p className="form-note" role="status">{mutationReadOnlyMessage}</p>}
        <div className="dialog-actions transaction-detail-actions">
          <button className="ghost-button" onClick={onClose} type="button">Close</button>
          {isOccurrence && isRecurring && (
            <button
              className="ghost-button"
              onClick={() => onStopFutureOccurrences(transaction.id, transaction.date)}
              disabled={!canEdit}
              title={!canEdit ? mutationReadOnlyMessage : "Stop future occurrences"}
              type="button"
            >
              Stop future occurrences
            </button>
          )}
          <button
            className="danger-action"
            onClick={() => onDelete(transaction.id)}
            disabled={!canDelete}
            title={!canDelete ? mutationReadOnlyMessage : isRecurring ? "Delete recurring series" : "Delete transaction"}
            type="button"
          >
            <Trash2 size={17} aria-hidden="true" />
            {isRecurring ? "Delete recurring series" : "Delete"}
          </button>
          <button
            className="primary-action"
            onClick={onEdit}
            disabled={!canEdit}
            title={!canEdit ? mutationReadOnlyMessage : "Edit transaction"}
            type="button"
          >
            Edit transaction
          </button>
        </div>
      </div>
    </div>
  );
}

function TransactionList({
  transactions,
  settings,
  members,
  onOpenTransaction
}: {
  transactions: BudgetTransaction[];
  settings: BudgetSettings;
  members: BudgetMember[];
  onOpenTransaction: (transaction: BudgetTransaction) => void;
}) {
  const memberById = new Map(members.map((member) => [member.id, member]));

  return (
    <div className="compact-list">
      {transactions.length === 0 ? (
        <div className="empty-state">No transactions in this view.</div>
      ) : (
        transactions.map((transaction) => {
          const member = memberById.get(transaction.createdByMemberId);
          return (
            <div
              key={transaction.id}
              className="compact-row compact-row-open"
              role="button"
              tabIndex={0}
              aria-label={`Open details for ${transaction.title}`}
              onClick={() => onOpenTransaction(transaction)}
              onKeyDown={(event) => activateTransactionOnKeyDown(event, () => onOpenTransaction(transaction))}
            >
              <span className={`transaction-icon ${transaction.type}`} aria-hidden="true">
                {transaction.type === "income" ? <ArrowUpCircle size={17} /> : <ArrowDownCircle size={17} />}
              </span>
              <div>
                <strong>{transaction.title}</strong>
                <span>
                  {categoryName(transaction.category)} · {member ? member.displayName : "Member unavailable"}
                </span>
              </div>
              <b className={transaction.type}>
                {transaction.type === "expense" ? "-" : "+"}
                {formatAmountNumber(transaction.amount, settings.currencyCode)}
                <small>{formatShortDate(transaction.date)}</small>
              </b>
            </div>
          );
        })
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

function MemberBadge({ member, compact = false }: { member: BudgetMember; compact?: boolean }) {
  return (
    <span
      className="member-badge"
      style={{
        backgroundColor: member.color,
        "--member-text-color": contrastTextColor(member.color)
      } as CSSProperties}
    >
      {compact ? member.initials.slice(0, 1) : member.initials}
    </span>
  );
}

export { App };
