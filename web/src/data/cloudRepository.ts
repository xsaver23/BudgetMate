import type { User } from "@supabase/supabase-js";
import { supabase } from "./supabaseClient";
import { defaultBudgetSettings } from "../domain/defaults";
import { monthlyBudget } from "../domain/budgetMath";
import type {
  AppState,
  Budget,
  BudgetInvite,
  BudgetMember,
  BudgetSettings,
  BudgetTransaction,
  MemberRole,
  Settlement,
  TransactionSplit
} from "../domain/types";

type BudgetRow = {
  id: string;
  owner_user_id: string;
  name: string;
  created_at?: string;
  updated_at?: string;
};

type MembershipRow = {
  budget_id: string;
  user_id: string;
  role: "owner" | "member";
  status: "active" | "invited" | "pending";
};

type SettingsRow = {
  user_id: string;
  budget_id: string;
  monthly_budget: number | string;
  currency_code: string;
  appearance: "system" | "light" | "dark";
  category_budgets: Record<string, number> | null;
  category_emojis: Record<string, string> | null;
};

type MemberRow = {
  id: string;
  user_id: string;
  budget_id: string;
  display_name: string;
  email: string | null;
  initials: string;
  color: string;
  auth_user_id: string | null;
  role: "owner" | "member";
  invite_status: "active" | "invited" | "pending";
  joined_date: string | null;
  created_date: string;
};

type TransactionRow = {
  id: string;
  user_id: string;
  budget_id: string;
  title: string;
  amount: number | string;
  type: "income" | "expense";
  category: string;
  payment_method: "cash" | "card" | "paypal" | null;
  created_by_member_id: string;
  date: string;
  created_at: string;
  recurrence_rule: string | null;
  splits: Array<{ id: string; member_id?: string; memberId?: string; amount: number | string }> | null;
};

type SettlementRow = {
  id: string;
  user_id: string;
  budget_id: string;
  from_member_id: string;
  to_member_id: string;
  amount: number | string;
  date: string;
};

type InviteRow = {
  id: string;
  budget_id: string;
  invited_by_user_id: string;
  display_name: string;
  email: string;
  status: "pending" | "accepted" | "declined" | "cancelled";
  created_at: string;
};

const palette = ["#3B8FE2", "#E2572E", "#1FA37D", "#7B6EE6"];

function swiftISODate(value: string | Date = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  const safeDate = Number.isNaN(date.getTime()) ? new Date() : date;
  return safeDate.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function requireSupabase() {
  if (!supabase) {
    throw new Error("Supabase is not configured for the web app.");
  }
  return supabase;
}

function normalizeEmail(email?: string | null) {
  const normalized = email?.trim().toLowerCase() ?? "";
  return normalized || undefined;
}

function initialsFromName(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length >= 2) {
    return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  }
  return parts[0]?.[0]?.toUpperCase() ?? "?";
}

function safeName(user: User) {
  const emailPrefix = user.email?.split("@")[0] ?? "You";
  const name = (user.user_metadata?.display_name as string | undefined) ?? emailPrefix;
  return name.trim() || "You";
}

function mapBudget(row: BudgetRow): Budget {
  return {
    id: row.id,
    ownerUserId: row.owner_user_id,
    name: row.name,
    createdAt: row.created_at ?? swiftISODate(),
    updatedAt: row.updated_at ?? row.created_at ?? swiftISODate()
  };
}

function mapSettings(row: SettingsRow): BudgetSettings {
  return {
    budgetId: row.budget_id,
    currencyCode: row.currency_code ?? "USD",
    appearance: row.appearance ?? "system",
    categoryBudgets: row.category_budgets ?? {},
    categoryEmojis: row.category_emojis ?? {}
  };
}

function mapMember(row: MemberRow): BudgetMember {
  return {
    id: row.id,
    budgetId: row.budget_id,
    displayName: row.display_name,
    email: row.email ?? undefined,
    initials: row.initials,
    color: row.color,
    authUserId: row.auth_user_id ?? undefined,
    role: row.role,
    inviteStatus: row.invite_status,
    joinedDate: row.joined_date ?? undefined,
    createdDate: row.created_date
  };
}

function memberRoleKey(budgetId: string, userId: string) {
  return `${budgetId}:${userId}`;
}

function memberIdentityKeys(member: BudgetMember) {
  const keys = [`id:${member.budgetId}:${member.id}`];
  const normalizedEmail = normalizeEmail(member.email);

  if (member.authUserId) {
    keys.push(`auth:${member.budgetId}:${member.authUserId}`);
  }
  if (normalizedEmail) {
    keys.push(`email:${member.budgetId}:${normalizedEmail}`);
  }

  return keys;
}

function applyMembershipRoles(members: BudgetMember[], memberships: MembershipRow[]) {
  const rolesByBudgetUser = new Map<string, MemberRole>();

  memberships
    .filter((membership) => membership.status === "active")
    .forEach((membership) => {
      rolesByBudgetUser.set(memberRoleKey(membership.budget_id, membership.user_id), membership.role);
    });

  return members.map((member) => {
    const membershipRole = member.authUserId
      ? rolesByBudgetUser.get(memberRoleKey(member.budgetId, member.authUserId))
      : undefined;

    return membershipRole && membershipRole !== member.role
      ? { ...member, role: membershipRole }
      : member;
  });
}

function memberPreferenceScore(member: BudgetMember) {
  let score = 0;
  if (member.inviteStatus === "active") score += 100;
  if (member.authUserId) score += 80;
  if (member.joinedDate) score += 20;
  if (member.email) score += 10;
  if (member.role === "owner") score += 5;
  return score;
}

function mergeMemberIdentity(left: BudgetMember, right: BudgetMember): BudgetMember {
  const preferred = memberPreferenceScore(right) > memberPreferenceScore(left) ? right : left;
  const fallback = preferred === left ? right : left;

  return {
    ...preferred,
    displayName: preferred.displayName.trim() || fallback.displayName,
    email: normalizeEmail(preferred.email) ?? normalizeEmail(fallback.email),
    initials: preferred.initials || fallback.initials,
    color: preferred.color || fallback.color,
    authUserId: preferred.authUserId ?? fallback.authUserId,
    inviteStatus: preferred.inviteStatus === "active" || fallback.inviteStatus === "active" ? "active" : preferred.inviteStatus,
    joinedDate: preferred.joinedDate ?? fallback.joinedDate,
    createdDate: preferred.createdDate || fallback.createdDate
  };
}

function deduplicateMembersForBudget(members: BudgetMember[]) {
  const membersByKey = new Map<string, BudgetMember>();
  const primaryKeyByKey = new Map<string, string>();

  for (const member of members) {
    const keys = memberIdentityKeys(member);
    const existingPrimaryKey = keys.map((key) => primaryKeyByKey.get(key)).find(Boolean);

    if (!existingPrimaryKey) {
      const primaryKey = keys[0];
      membersByKey.set(primaryKey, member);
      keys.forEach((key) => primaryKeyByKey.set(key, primaryKey));
      continue;
    }

    const existing = membersByKey.get(existingPrimaryKey);
    const merged = existing ? mergeMemberIdentity(existing, member) : member;
    const mergedKeys = Array.from(new Set([...keys, ...memberIdentityKeys(merged)]));
    membersByKey.set(existingPrimaryKey, merged);
    mergedKeys.forEach((key) => primaryKeyByKey.set(key, existingPrimaryKey));
  }

  return Array.from(membersByKey.values()).sort((left, right) => {
    if (left.role !== right.role) {
      return left.role === "owner" ? -1 : 1;
    }
    if (left.inviteStatus !== right.inviteStatus) {
      return left.inviteStatus === "active" ? -1 : 1;
    }
    return left.displayName.localeCompare(right.displayName);
  });
}

function mapSplits(splits: TransactionRow["splits"]): TransactionSplit[] {
  return (splits ?? []).map((split) => ({
    id: split.id,
    memberId: split.member_id ?? split.memberId ?? "",
    amount: Number(split.amount)
  })).filter((split) => split.memberId && split.amount > 0);
}

function mapTransaction(row: TransactionRow): BudgetTransaction {
  return {
    id: row.id,
    budgetId: row.budget_id,
    userId: row.user_id,
    title: row.title,
    amount: Number(row.amount),
    type: row.type,
    category: row.category,
    paymentMethod: row.payment_method ?? undefined,
    createdByMemberId: row.created_by_member_id,
    date: row.date,
    createdAt: row.created_at,
    recurrenceRule: row.recurrence_rule ?? undefined,
    splits: mapSplits(row.splits)
  };
}

function mapSettlement(row: SettlementRow): Settlement {
  return {
    id: row.id,
    budgetId: row.budget_id,
    userId: row.user_id,
    fromMemberId: row.from_member_id,
    toMemberId: row.to_member_id,
    amount: Number(row.amount),
    date: row.date
  };
}

function mapInvite(row: InviteRow): BudgetInvite {
  return {
    id: row.id,
    budgetId: row.budget_id,
    invitedByUserId: row.invited_by_user_id,
    displayName: row.display_name,
    email: row.email,
    status: row.status,
    createdAt: row.created_at
  };
}

function settingsRow(settings: BudgetSettings, userId: string): SettingsRow {
  return {
    user_id: userId,
    budget_id: settings.budgetId,
    monthly_budget: monthlyBudget(settings),
    currency_code: settings.currencyCode,
    appearance: settings.appearance,
    category_budgets: settings.categoryBudgets,
    category_emojis: settings.categoryEmojis
  };
}

function memberRow(member: BudgetMember, userId: string): MemberRow {
  return {
    id: member.id,
    user_id: userId,
    budget_id: member.budgetId,
    display_name: member.displayName,
    email: member.email ?? null,
    initials: member.initials,
    color: member.color,
    auth_user_id: member.authUserId ?? null,
    role: member.role,
    invite_status: member.inviteStatus,
    joined_date: member.joinedDate ? swiftISODate(member.joinedDate) : null,
    created_date: swiftISODate(member.createdDate)
  };
}

function transactionRow(transaction: BudgetTransaction, userId: string): TransactionRow {
  return {
    id: transaction.id,
    user_id: userId,
    budget_id: transaction.budgetId,
    title: transaction.title,
    amount: transaction.amount,
    type: transaction.type,
    category: transaction.category,
    payment_method: transaction.paymentMethod ?? null,
    created_by_member_id: transaction.createdByMemberId,
    date: swiftISODate(transaction.date),
    created_at: swiftISODate(transaction.createdAt),
    recurrence_rule: transaction.recurrenceRule ?? null,
    splits: transaction.splits.map((split) => ({
      id: split.id,
      member_id: split.memberId,
      amount: split.amount
    }))
  };
}

export async function signInWithEmail(email: string, password: string) {
  const client = requireSupabase();
  const { data, error } = await client.auth.signInWithPassword({
    email: email.trim().toLowerCase(),
    password
  });
  if (error) throw error;
  return data.session;
}

export async function signUpWithEmail(email: string, password: string, displayName: string) {
  const client = requireSupabase();
  const { data, error } = await client.auth.signUp({
    email: email.trim().toLowerCase(),
    password,
    options: {
      data: {
        display_name: displayName.trim()
      }
    }
  });
  if (error) throw error;
  return data.session;
}

export async function signOut() {
  const client = requireSupabase();
  const { error } = await client.auth.signOut();
  if (error) throw error;
}

export async function ensurePersonalBudget(user: User) {
  const client = requireSupabase();
  const now = swiftISODate();
  const userId = user.id;
  const email = normalizeEmail(user.email);

  const budget: BudgetRow = {
    id: userId,
    owner_user_id: userId,
    name: "My Budget",
    created_at: now,
    updated_at: now
  };
  const membership: MembershipRow = {
    budget_id: userId,
    user_id: userId,
    role: "owner",
    status: "active"
  };
  const ownerMember: MemberRow = {
    id: userId,
    user_id: userId,
    budget_id: userId,
    display_name: safeName(user),
    email: email ?? null,
    initials: initialsFromName(safeName(user)),
    color: palette[0],
    auth_user_id: userId,
    role: "owner",
    invite_status: "active",
    joined_date: now,
    created_date: now
  };

  const { error: budgetError } = await client.from("budgets").upsert(budget, { onConflict: "id" });
  if (budgetError) throw budgetError;

  const { error: membershipError } = await client
    .from("budget_memberships")
    .upsert(membership, { onConflict: "budget_id,user_id" });
  if (membershipError) throw membershipError;

  const { data: existingMembers, error: memberFetchError } = await client
    .from("budget_members")
    .select("id,auth_user_id,email")
    .eq("budget_id", userId);
  if (memberFetchError) throw memberFetchError;

  const hasProfile = (existingMembers ?? []).some((member) => {
    const row = member as { id: string; auth_user_id: string | null; email: string | null };
    return row.id === userId || row.auth_user_id === userId || normalizeEmail(row.email) === email;
  });

  if (!hasProfile) {
    const { error: memberError } = await client.from("budget_members").upsert(ownerMember, { onConflict: "id" });
    if (memberError) throw memberError;
  }
}

export async function fetchCloudState(user: User, preferredBudgetId?: string): Promise<AppState> {
  const client = requireSupabase();
  await ensurePersonalBudget(user);

  const { data: membershipData, error: membershipError } = await client
    .from("budget_memberships")
    .select()
    .eq("user_id", user.id)
    .eq("status", "active");
  if (membershipError) throw membershipError;

  const memberships = (membershipData ?? []) as MembershipRow[];
  const budgetIds = Array.from(new Set([user.id, ...memberships.map((membership) => membership.budget_id)]));

  const { data: budgetData, error: budgetError } = await client.from("budgets").select().in("id", budgetIds);
  if (budgetError) throw budgetError;

  const budgetsById = new Map(((budgetData ?? []) as BudgetRow[]).map((row) => [row.id, mapBudget(row)]));
  if (!budgetsById.has(user.id)) {
    budgetsById.set(user.id, {
      id: user.id,
      ownerUserId: user.id,
      name: "My Budget",
      createdAt: swiftISODate(),
      updatedAt: swiftISODate()
    });
  }

  const [settingsResult, membersResult, membershipsResult, transactionsResult, settlementsResult] = await Promise.all([
    client.from("budget_settings").select().in("budget_id", budgetIds),
    client.from("budget_members").select().in("budget_id", budgetIds),
    client.from("budget_memberships").select().in("budget_id", budgetIds).eq("status", "active"),
    client.from("budget_transactions").select().in("budget_id", budgetIds),
    client.from("budget_settlements").select().in("budget_id", budgetIds)
  ]);

  if (settingsResult.error) throw settingsResult.error;
  if (membersResult.error) throw membersResult.error;
  if (membershipsResult.error) throw membershipsResult.error;
  if (transactionsResult.error) throw transactionsResult.error;
  if (settlementsResult.error) throw settlementsResult.error;

  const settingsRows = (settingsResult.data ?? []) as SettingsRow[];
  const settingsByBudgetId = Object.fromEntries(settingsRows.map((row) => [row.budget_id, mapSettings(row)]));
  for (const budgetId of budgetIds) {
    if (!settingsByBudgetId[budgetId]) {
      settingsByBudgetId[budgetId] = defaultBudgetSettings(budgetId);
    }
  }

  const budgets = [...budgetsById.values()].sort((left, right) => {
    if (left.id === user.id) return -1;
    if (right.id === user.id) return 1;
    return left.name.localeCompare(right.name);
  });

  const currentBudgetId =
    preferredBudgetId && budgetIds.includes(preferredBudgetId)
      ? preferredBudgetId
      : budgetIds.includes(user.id)
        ? user.id
        : budgetIds[0];

  const cloudMembers = ((membersResult.data ?? []) as MemberRow[]).map(mapMember);
  const allMemberships = (membershipsResult.data ?? []) as MembershipRow[];
  const normalizedMembers = deduplicateMembersForBudget(applyMembershipRoles(cloudMembers, allMemberships));

  return {
    budgets,
    currentBudgetId,
    currentUserId: user.id,
    members: normalizedMembers,
    transactions: ((transactionsResult.data ?? []) as TransactionRow[]).map(mapTransaction),
    settlements: ((settlementsResult.data ?? []) as SettlementRow[]).map(mapSettlement),
    settingsByBudgetId
  };
}

export async function upsertCloudSettings(settings: BudgetSettings, userId: string) {
  const client = requireSupabase();
  const { error } = await client.from("budget_settings").upsert(settingsRow(settings, userId), { onConflict: "budget_id" });
  if (error) throw error;
}

export async function upsertCloudMember(member: BudgetMember, userId: string) {
  const client = requireSupabase();
  const { error } = await client.from("budget_members").upsert(memberRow(member, userId), { onConflict: "id" });
  if (error) throw error;
}

export async function createCloudSharedBudget(name: string, user: User): Promise<string> {
  const client = requireSupabase();
  await ensurePersonalBudget(user);

  const budgetId = crypto.randomUUID();
  const now = swiftISODate();
  const budgetName = name.trim() || "Shared Budget";
  const budget: BudgetRow = {
    id: budgetId,
    owner_user_id: user.id,
    name: budgetName,
    created_at: now,
    updated_at: now
  };
  const membership: MembershipRow = {
    budget_id: budgetId,
    user_id: user.id,
    role: "owner",
    status: "active"
  };
  const ownerMember: MemberRow = {
    id: crypto.randomUUID(),
    user_id: user.id,
    budget_id: budgetId,
    display_name: safeName(user),
    email: normalizeEmail(user.email) ?? null,
    initials: initialsFromName(safeName(user)),
    color: palette[0],
    auth_user_id: user.id,
    role: "owner",
    invite_status: "active",
    joined_date: now,
    created_date: now
  };

  const { error: budgetError } = await client.from("budgets").insert(budget);
  if (budgetError) throw budgetError;

  const { error: membershipError } = await client
    .from("budget_memberships")
    .upsert(membership, { onConflict: "budget_id,user_id" });
  if (membershipError) throw membershipError;

  const { error: memberError } = await client.from("budget_members").upsert(ownerMember, { onConflict: "id" });
  if (memberError) throw memberError;

  const { error: settingsError } = await client
    .from("budget_settings")
    .upsert(settingsRow(defaultBudgetSettings(budgetId), user.id), { onConflict: "budget_id" });
  if (settingsError) throw settingsError;

  return budgetId;
}

export async function createCloudInvite(member: BudgetMember, userId: string) {
  const client = requireSupabase();
  const normalizedEmail = normalizeEmail(member.email);
  await upsertCloudMember(member, userId);

  if (!normalizedEmail) {
    return;
  }

  const invite: InviteRow = {
    id: crypto.randomUUID(),
    budget_id: member.budgetId,
    invited_by_user_id: userId,
    display_name: member.displayName,
    email: normalizedEmail,
    status: "pending",
    created_at: swiftISODate()
  };

  const { error } = await client.from("budget_invites").upsert(invite, { onConflict: "budget_id,email" });
  if (error) throw error;
}

export async function upsertCloudTransaction(transaction: BudgetTransaction, userId: string) {
  const client = requireSupabase();
  const { error } = await client
    .from("budget_transactions")
    .upsert(transactionRow(transaction, userId), { onConflict: "id" });
  if (error) throw error;
}

export async function deleteCloudTransaction(transactionId: string, budgetId: string) {
  const client = requireSupabase();
  const { error } = await client.from("budget_transactions").delete().eq("id", transactionId).eq("budget_id", budgetId);
  if (error) throw error;
}

export async function fetchPendingInvites(email: string): Promise<BudgetInvite[]> {
  const client = requireSupabase();
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) {
    return [];
  }

  const { data, error } = await client
    .from("budget_invites")
    .select()
    .eq("email", normalizedEmail)
    .eq("status", "pending");
  if (error) throw error;
  return ((data ?? []) as InviteRow[]).map(mapInvite);
}

export async function acceptCloudInvite(invite: BudgetInvite, userId: string) {
  const client = requireSupabase();
  const now = swiftISODate();

  const membership: MembershipRow = {
    budget_id: invite.budgetId,
    user_id: userId,
    role: "member",
    status: "active"
  };

  const { error: membershipError } = await client
    .from("budget_memberships")
    .upsert(membership, { onConflict: "budget_id,user_id" });
  if (membershipError) throw membershipError;

  const { error: memberError } = await client
    .from("budget_members")
    .update({
      auth_user_id: userId,
      invite_status: "active",
      joined_date: now
    })
    .eq("budget_id", invite.budgetId)
    .eq("email", invite.email.toLowerCase());
  if (memberError) throw memberError;

  const { error: inviteError } = await client
    .from("budget_invites")
    .update({
      status: "accepted",
      accepted_at: now,
      accepted_by_user_id: userId
    })
    .eq("id", invite.id);
  if (inviteError) throw inviteError;
}
