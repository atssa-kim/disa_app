-- 시설현황(facility) 기능 스키마 (2026-09-10)
-- Supabase SQL Editor에서 1회 실행하세요.
--
-- 설계:
--   - 카테고리(facility_categories)를 데이터로 관리 → 새 시설 카테고리를 추가할 때
--     코드 배포 없이 이 테이블에 행만 추가하면 됨 (예: 주방자동소화장치, 수계, 냉난방배관 등).
--   - 읽기(SELECT)는 기존 disaster_roles/disaster_tasks와 동일하게 anon key로 전체 공개.
--   - 쓰기(INSERT/UPDATE/DELETE)는 supabase_auth_setup.sql에서 만든 app_admins 테이블 재사용
--     → 마스터 관리자로 로그인된 사용자만 수정 가능 (재난별 세분 권한이 필요해지면 나중에
--     disaster_editors처럼 facility_editors 테이블을 추가하면 됨).
--   - attrs jsonb: 카테고리마다 부가정보 항목이 달라도(점검일자, 배관구경 등) 스키마 변경 없이 수용.

create table if not exists public.facility_categories (
  id bigint generated always as identity primary key,
  disaster text,                 -- '화재'|'정전'|'누수'|... (twin-alarm/disa_app 재난 키 재사용) / null=공통
  label text not null,           -- 화면 표시명, 예: "실외기 현황"
  icon text,                     -- emoji 1개
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.facility_items (
  id bigint generated always as identity primary key,
  category_id bigint not null references public.facility_categories(id) on delete cascade,
  name text not null,            -- 실내기 위치 등 항목을 대표하는 이름
  spec text,                     -- 모델명 등 규격
  qty text,
  building text,                 -- 동관/서관/중앙/공통
  floor text,                    -- 지하3층, 서관 1층, 동관 36층 등
  location text,                 -- 실외기 위치 등 물리적 위치
  note text,
  attrs jsonb not null default '{}'::jsonb,   -- 카테고리별 부가 정보 (예: {"breaker":"...","vendor":"..."})
  sort_order int not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.facility_drawings (
  id bigint generated always as identity primary key,
  category_id bigint not null references public.facility_categories(id) on delete cascade,
  title text not null,           -- 예: "실외기실 위치_B1층"
  building text,
  floor text,
  storage_path text not null,    -- Storage 버킷('facility-drawings') 내 경로
  sort_order int not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.facility_categories enable row level security;
alter table public.facility_items      enable row level security;
alter table public.facility_drawings   enable row level security;

drop policy if exists "fc_read_all" on public.facility_categories;
create policy "fc_read_all" on public.facility_categories for select using (true);
drop policy if exists "fi_read_all" on public.facility_items;
create policy "fi_read_all" on public.facility_items for select using (true);
drop policy if exists "fd_read_all" on public.facility_drawings;
create policy "fd_read_all" on public.facility_drawings for select using (true);

drop policy if exists "fc_write_admin" on public.facility_categories;
create policy "fc_write_admin" on public.facility_categories for all
  using (exists (select 1 from public.app_admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.app_admins a where a.user_id = auth.uid()));

drop policy if exists "fi_write_admin" on public.facility_items;
create policy "fi_write_admin" on public.facility_items for all
  using (exists (select 1 from public.app_admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.app_admins a where a.user_id = auth.uid()));

drop policy if exists "fd_write_admin" on public.facility_drawings;
create policy "fd_write_admin" on public.facility_drawings for all
  using (exists (select 1 from public.app_admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.app_admins a where a.user_id = auth.uid()));

-- Storage 버킷: 'facility-drawings' (public read). 대시보드에서 만들거나 아래로 생성:
insert into storage.buckets (id, name, public)
values ('facility-drawings', 'facility-drawings', true)
on conflict (id) do nothing;

drop policy if exists "facility_drawings_public_read" on storage.objects;
create policy "facility_drawings_public_read" on storage.objects for select
  using (bucket_id = 'facility-drawings');

drop policy if exists "facility_drawings_admin_write" on storage.objects;
create policy "facility_drawings_admin_write" on storage.objects for all
  using (
    bucket_id = 'facility-drawings'
    and exists (select 1 from public.app_admins a where a.user_id = auth.uid())
  )
  with check (
    bucket_id = 'facility-drawings'
    and exists (select 1 from public.app_admins a where a.user_id = auth.uid())
  );
