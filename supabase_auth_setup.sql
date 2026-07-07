-- disa_app 파트장별 임무 수정 권한 (2026-07-07)
-- Supabase SQL Editor에서 1회 실행하세요. 실행 후 scripts/setup-disaster-editors.ts
-- (twin-alarm 저장소)로 실제 로그인 계정과 매핑을 채웁니다.
--
-- 설계:
--   - disaster_roles/disaster_tasks 의 읽기(SELECT) 정책은 기존 그대로 둡니다
--     (twin-alarm은 anon key로 계속 조회 — Archive/supabase_rls.sql의 dr_read/dt_read 참고).
--   - 쓰기(INSERT/UPDATE/DELETE)는 이번에 새로 추가하는 두 테이블을 기준으로 허용합니다.
--     app_admins 에 있으면 전체 재난 수정 가능(마스터), disaster_editors 에 (내 계정, 재난)
--     행이 있으면 그 재난만 수정 가능.
--   - service_role key(seed/fix-badges 스크립트, 이 SQL 자체)는 RLS를 우회하므로 영향 없음.

-- 1. 마스터 계정(전체 재난 수정 가능) 목록
CREATE TABLE IF NOT EXISTS public.app_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  note    text
);
ALTER TABLE public.app_admins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "aa_read_own" ON public.app_admins;
CREATE POLICY "aa_read_own" ON public.app_admins FOR SELECT USING (auth.uid() = user_id);

-- 2. 재난별 담당 파트장(편집 권한) 매핑 — 한 사람이 여러 재난을 담당할 수 있음
CREATE TABLE IF NOT EXISTS public.disaster_editors (
  user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  disaster text NOT NULL,
  PRIMARY KEY (user_id, disaster)
);
ALTER TABLE public.disaster_editors ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "de_read_own" ON public.disaster_editors;
CREATE POLICY "de_read_own" ON public.disaster_editors FOR SELECT USING (auth.uid() = user_id);

-- 3. disaster_roles 쓰기 정책 — 마스터이거나, 이 role 행의 disaster를 담당하는 파트장만
DROP POLICY IF EXISTS "dr_write" ON public.disaster_roles;
CREATE POLICY "dr_write" ON public.disaster_roles
  FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.app_admins a WHERE a.user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.disaster_editors e
      WHERE e.user_id = auth.uid() AND e.disaster = disaster_roles.disaster
    )
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.app_admins a WHERE a.user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.disaster_editors e
      WHERE e.user_id = auth.uid() AND e.disaster = disaster_roles.disaster
    )
  );

-- 4. disaster_tasks 쓰기 정책 — role_id로 연결된 disaster_roles.disaster 기준으로 동일하게 판단
DROP POLICY IF EXISTS "dt_write" ON public.disaster_tasks;
CREATE POLICY "dt_write" ON public.disaster_tasks
  FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.app_admins a WHERE a.user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.disaster_roles r
      JOIN public.disaster_editors e ON e.disaster = r.disaster AND e.user_id = auth.uid()
      WHERE r.id = disaster_tasks.role_id
    )
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.app_admins a WHERE a.user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.disaster_roles r
      JOIN public.disaster_editors e ON e.disaster = r.disaster AND e.user_id = auth.uid()
      WHERE r.id = disaster_tasks.role_id
    )
  );
