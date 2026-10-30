-- ========================================================================
-- 20260813_create_unanswered_questions.sql
-- ========================================================================
create extension if not exists pgcrypto;

create table if not exists public.unanswered_questions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    question text not null check (char_length(question) between 1 and 2000),
    location text not null check (char_length(location) between 1 and 200),
    category text not null default 'pending_review',
    status text not null default 'unanswered'
        check (status in ('unanswered', 'reviewing', 'answered', 'dismissed')),
    notification_requested boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.unanswered_questions enable row level security;

drop policy if exists "Users can add their own unanswered questions"
    on public.unanswered_questions;
create policy "Users can add their own unanswered questions"
    on public.unanswered_questions
    for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can read their own unanswered questions"
    on public.unanswered_questions;
create policy "Users can read their own unanswered questions"
    on public.unanswered_questions
    for select
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own notification preference"
    on public.unanswered_questions;
create policy "Users can update their own notification preference"
    on public.unanswered_questions
    for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

grant select, insert on public.unanswered_questions to authenticated;
revoke update on public.unanswered_questions from authenticated;
grant update (notification_requested) on public.unanswered_questions to authenticated;

create index if not exists unanswered_questions_created_at_idx
    on public.unanswered_questions (created_at desc);

create index if not exists unanswered_questions_category_status_idx
    on public.unanswered_questions (category, status);

-- ========================================================================
-- 20260818_create_chat_history.sql
-- ========================================================================
create extension if not exists pgcrypto;

create table if not exists public.chat_conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    title text not null default 'New chat' check (char_length(title) between 1 and 120),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    role text not null check (role in ('user', 'assistant')),
    content text not null check (char_length(content) between 1 and 8000),
    answer_state text check (
        answer_state is null or answer_state in (
            'setup', 'cited', 'abstained', 'out_of_scope', 'forecast_unavailable',
            'service_unavailable'
        )
    ),
    source_title text check (source_title is null or char_length(source_title) <= 300),
    source_url text check (source_url is null or char_length(source_url) <= 2000),
    created_at timestamptz not null default now()
);

alter table public.chat_conversations enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "Users can create their own conversations"
    on public.chat_conversations;
create policy "Users can create their own conversations"
    on public.chat_conversations
    for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can read their own conversations"
    on public.chat_conversations;
create policy "Users can read their own conversations"
    on public.chat_conversations
    for select
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own conversations"
    on public.chat_conversations;
create policy "Users can update their own conversations"
    on public.chat_conversations
    for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own conversations"
    on public.chat_conversations;
create policy "Users can delete their own conversations"
    on public.chat_conversations
    for delete
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "Users can create messages in their own conversations"
    on public.chat_messages;
create policy "Users can create messages in their own conversations"
    on public.chat_messages
    for insert
    to authenticated
    with check (
        (select auth.uid()) = user_id
        and exists (
            select 1
            from public.chat_conversations conversation
            where conversation.id = conversation_id
              and conversation.user_id = (select auth.uid())
        )
    );

drop policy if exists "Users can read messages in their own conversations"
    on public.chat_messages;
create policy "Users can read messages in their own conversations"
    on public.chat_messages
    for select
    to authenticated
    using (
        (select auth.uid()) = user_id
        and exists (
            select 1
            from public.chat_conversations conversation
            where conversation.id = conversation_id
              and conversation.user_id = (select auth.uid())
        )
    );

drop policy if exists "Users can delete messages in their own conversations"
    on public.chat_messages;
create policy "Users can delete messages in their own conversations"
    on public.chat_messages
    for delete
    to authenticated
    using (
        (select auth.uid()) = user_id
        and exists (
            select 1
            from public.chat_conversations conversation
            where conversation.id = conversation_id
              and conversation.user_id = (select auth.uid())
        )
    );

grant select, insert, update, delete on public.chat_conversations to authenticated;
grant select, insert, delete on public.chat_messages to authenticated;

create index if not exists chat_conversations_user_updated_idx
    on public.chat_conversations (user_id, updated_at desc);

create index if not exists chat_messages_conversation_created_idx
    on public.chat_messages (conversation_id, created_at asc);

create or replace function public.touch_chat_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.chat_conversations
    set updated_at = now()
    where id = new.conversation_id
      and user_id = new.user_id;
    return new;
end;
$$;

revoke all on function public.touch_chat_conversation() from public;

drop trigger if exists touch_conversation_after_message on public.chat_messages;
create trigger touch_conversation_after_message
after insert on public.chat_messages
for each row execute function public.touch_chat_conversation();

-- ========================================================================
-- 20260819_align_question_length_limit.sql
-- ========================================================================
-- Match the database limit to the FastAPI request schema and iOS composer.
alter table public.unanswered_questions
    drop constraint if exists unanswered_questions_question_check;

alter table public.unanswered_questions
    add constraint unanswered_questions_question_check
    check (char_length(question) between 1 and 2000);

-- ========================================================================
-- 20260819_allow_service_unavailable_chat_state.sql
-- ========================================================================
-- Keep existing chat-history installations in sync with the iOS answer states.
-- The original table predates the explicit state used for temporary AI outages.
alter table public.chat_messages
    drop constraint if exists chat_messages_answer_state_check;

alter table public.chat_messages
    add constraint chat_messages_answer_state_check check (
        answer_state is null or answer_state in (
            'setup',
            'cited',
            'abstained',
            'out_of_scope',
            'forecast_unavailable',
            'service_unavailable'
        )
    );

-- ========================================================================
-- 20260820_create_information_gap_clusters.sql
-- ========================================================================
-- Box 6 of the research pipeline: group similar, genuine information gaps.
--
-- This is deliberately a lightweight MVP clustering layer. PostgreSQL trigram
-- similarity is transparent, inexpensive, and suitable while the prototype has
-- a small question set. It can later be replaced by embeddings or BERTopic
-- without changing the iOS question-logging contract.

create extension if not exists pg_trgm;

alter table public.unanswered_questions
    add column if not exists confidence double precision,
    add column if not exists evidence_checked jsonb not null default '[]'::jsonb,
    add column if not exists assistant_response text;

alter table public.unanswered_questions
    drop constraint if exists unanswered_questions_confidence_check;

alter table public.unanswered_questions
    add constraint unanswered_questions_confidence_check
    check (confidence is null or (confidence >= 0 and confidence <= 1));

create table if not exists public.information_gap_clusters (
    id uuid primary key default gen_random_uuid(),
    representative_question text not null
        check (char_length(representative_question) between 1 and 2000),
    normalized_question text not null,
    location text not null check (char_length(location) between 1 and 200),
    category text not null,
    status text not null default 'candidate'
        check (status in ('candidate', 'reviewing', 'investigating', 'dismissed', 'published')),
    editorial_notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.unanswered_questions
    add column if not exists cluster_id uuid
        references public.information_gap_clusters(id) on delete set null;

create index if not exists unanswered_questions_cluster_id_idx
    on public.unanswered_questions (cluster_id);

create index if not exists information_gap_clusters_lookup_idx
    on public.information_gap_clusters (category, location, updated_at desc);

create index if not exists information_gap_clusters_trigram_idx
    on public.information_gap_clusters using gin (normalized_question gin_trgm_ops);

create or replace function public.normalize_gap_question(input text)
returns text
language sql
immutable
strict
set search_path = public
as $$
    select trim(
        regexp_replace(
            regexp_replace(
                lower(input),
                '[^[:alnum:][:space:]]+',
                ' ',
                'g'
            ),
            '[[:space:]]+',
            ' ',
            'g'
        )
    );
$$;

create or replace function public.assign_information_gap_cluster()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    normalized text;
    matched_cluster_id uuid;
begin
    normalized := public.normalize_gap_question(new.question);

    select cluster.id
      into matched_cluster_id
      from public.information_gap_clusters as cluster
     where cluster.category = new.category
       and similarity(lower(cluster.location), lower(new.location)) >= 0.45
       and similarity(cluster.normalized_question, normalized) >= 0.42
     order by similarity(cluster.normalized_question, normalized) desc,
              cluster.updated_at desc
     limit 1
     for update skip locked;

    if matched_cluster_id is null then
        insert into public.information_gap_clusters (
            representative_question,
            normalized_question,
            location,
            category
        ) values (
            new.question,
            normalized,
            new.location,
            new.category
        )
        returning id into matched_cluster_id;
    else
        update public.information_gap_clusters
           set updated_at = now()
         where id = matched_cluster_id;
    end if;

    new.cluster_id := matched_cluster_id;
    return new;
end;
$$;

revoke all on function public.assign_information_gap_cluster() from public;

drop trigger if exists assign_information_gap_cluster_before_write
    on public.unanswered_questions;
create trigger assign_information_gap_cluster_before_write
before insert or update of question, location, category
on public.unanswered_questions
for each row execute function public.assign_information_gap_cluster();

-- Put questions that were saved before this migration into an initial cluster.
update public.unanswered_questions
   set question = question
 where cluster_id is null;

alter table public.information_gap_clusters enable row level security;
revoke all on public.information_gap_clusters from anon, authenticated;

-- Journalist access is assigned in auth.users.raw_app_meta_data, never in
-- user-editable metadata. A new access token is required after changing a role.
create or replace function public.is_journalist()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(
        (auth.jwt() -> 'app_metadata' ->> 'role') in ('journalist', 'editor', 'admin'),
        false
    );
$$;

revoke all on function public.is_journalist() from public;
grant execute on function public.is_journalist() to authenticated;

create or replace function public.get_information_gap_clusters(
    minimum_questions integer default 1
)
returns table (
    cluster_id uuid,
    representative_question text,
    category text,
    status text,
    question_count bigint,
    unique_asker_count bigint,
    locations text[],
    question_examples text[],
    first_seen_at timestamptz,
    last_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not public.is_journalist() then
        raise exception 'Journalist access is required.' using errcode = '42501';
    end if;

    return query
    select
        cluster.id,
        cluster.representative_question,
        cluster.category,
        cluster.status,
        count(question.id)::bigint,
        count(distinct question.user_id)::bigint,
        array_agg(distinct question.location order by question.location),
        (array_agg(question.question order by question.created_at desc))[1:5],
        min(question.created_at),
        max(question.created_at)
    from public.information_gap_clusters as cluster
    join public.unanswered_questions as question
      on question.cluster_id = cluster.id
    group by cluster.id
    having count(question.id) >= greatest(minimum_questions, 1)
    order by count(question.id) desc, max(question.created_at) desc;
end;
$$;

revoke all on function public.get_information_gap_clusters(integer) from public;
grant execute on function public.get_information_gap_clusters(integer) to authenticated;


-- ========================================================================
-- 20260820_create_journalist_response_loop.sql
-- ========================================================================
-- Boxes 9-11: journalist review, verified response, user delivery, and reuse as
-- trusted evidence. All cross-user operations go through role-checked RPCs.

create table if not exists public.journalist_responses (
    id uuid primary key default gen_random_uuid(),
    cluster_id uuid not null unique
        references public.information_gap_clusters(id) on delete cascade,
    journalist_id uuid not null references auth.users(id) on delete restrict,
    response_text text not null check (char_length(response_text) between 1 and 8000),
    source_title text not null check (char_length(source_title) between 1 and 300),
    source_url text not null check (
        char_length(source_url) between 8 and 2000
        and source_url ~* '^https://'
    ),
    status text not null default 'draft'
        check (status in ('draft', 'published')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    published_at timestamptz
);

create table if not exists public.journalist_notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    cluster_id uuid not null
        references public.information_gap_clusters(id) on delete cascade,
    response_id uuid not null
        references public.journalist_responses(id) on delete cascade,
    created_at timestamptz not null default now(),
    read_at timestamptz,
    unique (user_id, response_id)
);

create index if not exists journalist_notifications_user_created_idx
    on public.journalist_notifications (user_id, created_at desc);

alter table public.journalist_responses enable row level security;
alter table public.journalist_notifications enable row level security;

revoke all on public.journalist_responses from anon, authenticated;
revoke all on public.journalist_notifications from anon, authenticated;

-- Save a draft or publish a verified answer. Publishing atomically resolves the
-- underlying questions and creates private notifications for their askers.
create or replace function public.save_journalist_response(
    target_cluster_id uuid,
    answer_text text,
    answer_source_title text,
    answer_source_url text,
    publish boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    saved_response_id uuid;
begin
    if not public.is_journalist() then
        raise exception 'Journalist access is required.' using errcode = '42501';
    end if;

    if not exists (
        select 1 from public.information_gap_clusters where id = target_cluster_id
    ) then
        raise exception 'Information-gap topic was not found.' using errcode = 'P0002';
    end if;

    if char_length(trim(answer_text)) < 1 then
        raise exception 'A verified answer is required.' using errcode = '22023';
    end if;
    if char_length(trim(answer_source_title)) < 1 then
        raise exception 'A source title is required.' using errcode = '22023';
    end if;
    if trim(answer_source_url) !~* '^https://' then
        raise exception 'Use a complete HTTPS source URL.' using errcode = '22023';
    end if;

    if not publish and exists (
        select 1
        from public.journalist_responses
        where cluster_id = target_cluster_id
          and status = 'published'
    ) then
        raise exception 'A published answer can only be changed by publishing the verified update.'
            using errcode = '22023';
    end if;

    insert into public.journalist_responses (
        cluster_id,
        journalist_id,
        response_text,
        source_title,
        source_url,
        status,
        published_at
    ) values (
        target_cluster_id,
        auth.uid(),
        trim(answer_text),
        trim(answer_source_title),
        trim(answer_source_url),
        case when publish then 'published' else 'draft' end,
        case when publish then now() else null end
    )
    on conflict (cluster_id) do update
    set journalist_id = auth.uid(),
        response_text = excluded.response_text,
        source_title = excluded.source_title,
        source_url = excluded.source_url,
        status = case
            when public.journalist_responses.status = 'published' then 'published'
            else excluded.status
        end,
        published_at = case
            when public.journalist_responses.status = 'published'
                then public.journalist_responses.published_at
            when excluded.status = 'published' then now()
            else null
        end,
        updated_at = now()
    returning id into saved_response_id;

    if publish then
        update public.information_gap_clusters
        set status = 'published', updated_at = now()
        where id = target_cluster_id;

        update public.unanswered_questions
        set status = 'answered', updated_at = now()
        where cluster_id = target_cluster_id
          and status in ('unanswered', 'reviewing');

        insert into public.journalist_notifications (
            user_id,
            cluster_id,
            response_id
        )
        select distinct
            question.user_id,
            target_cluster_id,
            saved_response_id
        from public.unanswered_questions as question
        where question.cluster_id = target_cluster_id
          and question.notification_requested
        on conflict (user_id, response_id) do nothing;
    else
        update public.information_gap_clusters
        set status = 'reviewing', updated_at = now()
        where id = target_cluster_id
          and status in ('candidate', 'reviewing', 'investigating');
    end if;

    return saved_response_id;
end;
$$;

revoke all on function public.save_journalist_response(uuid, text, text, text, boolean) from public;
grant execute on function public.save_journalist_response(uuid, text, text, text, boolean) to authenticated;

create or replace function public.get_journalist_response(target_cluster_id uuid)
returns table (
    response_id uuid,
    response_text text,
    source_title text,
    source_url text,
    response_status text,
    updated_at timestamptz,
    published_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not public.is_journalist() then
        raise exception 'Journalist access is required.' using errcode = '42501';
    end if;

    return query
    select
        response.id,
        response.response_text,
        response.source_title,
        response.source_url,
        response.status,
        response.updated_at,
        response.published_at
    from public.journalist_responses as response
    where response.cluster_id = target_cluster_id;
end;
$$;

revoke all on function public.get_journalist_response(uuid) from public;
grant execute on function public.get_journalist_response(uuid) to authenticated;

create or replace function public.dismiss_information_gap(
    target_cluster_id uuid,
    reason text default 'Dismissed after journalist review.'
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not public.is_journalist() then
        raise exception 'Journalist access is required.' using errcode = '42501';
    end if;

    update public.information_gap_clusters
    set status = 'dismissed',
        editorial_notes = nullif(trim(reason), ''),
        updated_at = now()
    where id = target_cluster_id
      and status <> 'published';

    update public.unanswered_questions
    set status = 'dismissed', updated_at = now()
    where cluster_id = target_cluster_id
      and status in ('unanswered', 'reviewing');
end;
$$;

revoke all on function public.dismiss_information_gap(uuid, text) from public;
grant execute on function public.dismiss_information_gap(uuid, text) to authenticated;

-- Private in-app delivery. The RPC exposes only the signed-in user's own
-- notifications and never returns journalist or community contact information.
create or replace function public.get_my_journalist_notifications()
returns table (
    notification_id uuid,
    cluster_id uuid,
    original_question text,
    answer_text text,
    source_title text,
    source_url text,
    published_at timestamptz,
    read_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        notification.id,
        notification.cluster_id,
        coalesce(
            (
                select question.question
                from public.unanswered_questions as question
                where question.cluster_id = notification.cluster_id
                  and question.user_id = auth.uid()
                order by question.created_at desc
                limit 1
            ),
            cluster.representative_question
        ),
        response.response_text,
        response.source_title,
        response.source_url,
        response.published_at,
        notification.read_at
    from public.journalist_notifications as notification
    join public.journalist_responses as response
      on response.id = notification.response_id
     and response.status = 'published'
    join public.information_gap_clusters as cluster
      on cluster.id = notification.cluster_id
    where notification.user_id = auth.uid()
    order by response.published_at desc nulls last;
$$;

revoke all on function public.get_my_journalist_notifications() from public;
grant execute on function public.get_my_journalist_notifications() to authenticated;

create or replace function public.mark_journalist_notification_read(
    target_notification_id uuid
)
returns void
language sql
security definer
set search_path = public, auth
as $$
    update public.journalist_notifications
    set read_at = coalesce(read_at, now())
    where id = target_notification_id
      and user_id = auth.uid();
$$;

revoke all on function public.mark_journalist_notification_read(uuid) from public;
grant execute on function public.mark_journalist_notification_read(uuid) to authenticated;

-- Published journalist answers become retrievable trusted evidence. This uses
-- the prototype's explainable trigram baseline and can later move to pgvector.
create or replace function public.search_published_journalist_answers(
    query_text text,
    match_threshold double precision default 0.35
)
returns table (
    response_id uuid,
    representative_question text,
    answer_text text,
    source_title text,
    source_url text,
    published_at timestamptz,
    similarity_score double precision
)
language sql
stable
security definer
set search_path = public, auth, extensions
as $$
    select
        response.id,
        cluster.representative_question,
        response.response_text,
        response.source_title,
        response.source_url,
        response.published_at,
        similarity(
            cluster.normalized_question,
            public.normalize_gap_question(query_text)
        )::double precision as similarity_score
    from public.journalist_responses as response
    join public.information_gap_clusters as cluster
      on cluster.id = response.cluster_id
    where auth.uid() is not null
      and response.status = 'published'
      and similarity(
          cluster.normalized_question,
          public.normalize_gap_question(query_text)
      ) >= greatest(0.15, least(match_threshold, 0.90))
    order by similarity_score desc, response.published_at desc
    limit 3;
$$;

revoke all on function public.search_published_journalist_answers(text, double precision) from public;
grant execute on function public.search_published_journalist_answers(text, double precision) to authenticated;

-- ========================================================================
-- 20260820_refine_journalist_inbox_quality.sql
-- ========================================================================
-- Remove predictable source-limit questions from the active journalist inbox.
-- Nothing is deleted: existing misclassified rows are marked dismissed so the
-- research audit trail remains available.

update public.unanswered_questions
set status = 'dismissed', updated_at = now()
where status = 'unanswered'
  and (
      (
          category = 'weather'
          and question ~* '\m(weather|forecast|rain|snow|temperature)\M'
          and (
              question ~* '\m(after|in|next|for)\M[[:space:]]+([89]|[1-9][0-9]+)[[:space:]]+days?\M'
              or question ~* '\m(after|in|next|for)\M[[:space:]]+[2-9][0-9]*[[:space:]]+weeks?\M'
              or question ~* '\m(after|in|next|for)\M[[:space:]]+[1-9][0-9]*[[:space:]]+months?\M'
          )
      )
      or (
          category = 'events'
          and question ~* '\mwhen\M'
          and question ~* '\m(class|classes|semester|term|college|school|university)\M'
          and question ~* '\m(start|starts|begin|begins|open|opens)\M'
          and question !~* '\mwhy\M|\mcancel|\mclosed\M|\mdelay|\mproblem\M|\mimpact\M'
      )
  );

create or replace function public.get_information_gap_clusters(
    minimum_questions integer default 1
)
returns table (
    cluster_id uuid,
    representative_question text,
    category text,
    status text,
    question_count bigint,
    unique_asker_count bigint,
    locations text[],
    question_examples text[],
    first_seen_at timestamptz,
    last_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not public.is_journalist() then
        raise exception 'Journalist access is required.' using errcode = '42501';
    end if;

    return query
    select
        cluster.id,
        cluster.representative_question,
        cluster.category,
        cluster.status,
        count(question.id)::bigint,
        count(distinct question.user_id)::bigint,
        array_agg(distinct question.location order by question.location),
        (array_agg(question.question order by question.created_at desc))[1:5],
        min(question.created_at),
        max(question.created_at)
    from public.information_gap_clusters as cluster
    join public.unanswered_questions as question
      on question.cluster_id = cluster.id
     and question.status = 'unanswered'
    where cluster.status in ('candidate', 'reviewing', 'investigating')
    group by cluster.id
    having count(question.id) >= greatest(minimum_questions, 1)
    order by count(question.id) desc, max(question.created_at) desc;
end;
$$;

revoke all on function public.get_information_gap_clusters(integer) from public;
grant execute on function public.get_information_gap_clusters(integer) to authenticated;

create or replace function public.get_information_gap_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    result jsonb;
begin
    if not public.is_journalist() then
        raise exception 'Journalist access is required.' using errcode = '42501';
    end if;

    select jsonb_build_object(
        'topic_count', count(distinct question.cluster_id),
        'question_count', count(question.id),
        'unique_asker_count', count(distinct question.user_id)
    )
    into result
    from public.unanswered_questions as question
    join public.information_gap_clusters as cluster
      on cluster.id = question.cluster_id
    where question.status = 'unanswered'
      and cluster.status in ('candidate', 'reviewing', 'investigating');

    return result;
end;
$$;

revoke all on function public.get_information_gap_summary() from public;
grant execute on function public.get_information_gap_summary() to authenticated;

