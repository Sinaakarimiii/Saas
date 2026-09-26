\set ON_ERROR_STOP on
begin;
create temp table custody_fixture as select gen_random_uuid() org_id,gen_random_uuid() sender_id,
 gen_random_uuid() recipient_id,gen_random_uuid() role_id,gen_random_uuid() case_id,
 gen_random_uuid() device_id;
insert into auth.users(id,aud,role,email)
select sender_id,'authenticated','authenticated','custody-source@example.test' from custody_fixture
union all select recipient_id,'authenticated','authenticated','custody-target@example.test' from custody_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Custody test',sender_id from custody_fixture;
insert into public.roles(id,org_id,name,is_system)
select role_id,org_id,'Custody operators',false from custody_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,sender_id,role_id from custody_fixture
union all select org_id,recipient_id,role_id from custody_fixture;
insert into public.role_permissions(role_id,permission_key)
select role_id,key from custody_fixture cross join public.permissions where key in
('repair.case.view','custody.baseline.record','custody.transfer.release','custody.transfer.accept','custody.transfer.return');
insert into public.repair_devices(id,org_id,imei,first_verified_by,first_evidence)
select device_id,org_id,'123456789012345',sender_id,'label-photo' from custody_fixture;
insert into public.repair_cases(id,org_id,created_by,customer_name,device_model,issue,priority,source,
 received_at,receipt_method,device_location,device_custodian,verified_device_id,imei_evidence,imei_verified_by,imei_verified_at)
select case_id,org_id,sender_id,'Customer','Model','Issue','normal','walk_in',clock_timestamp(),
 'walk_in','Desk A','Operator A',device_id,'label-photo',sender_id,clock_timestamp() from custody_fixture;
grant select on custody_fixture to authenticated;
set local role authenticated;
do $$
declare f record; v_transfer uuid; v_response jsonb; v_key uuid;
begin
 select * into f from custody_fixture;
 perform set_config('request.jwt.claim.sub',f.sender_id::text,true);
 perform public.record_repair_device_custody_baseline(f.org_id,f.case_id,'Desk A',f.sender_id,'baseline-proof',1,gen_random_uuid());
 v_key:=gen_random_uuid();
 v_response:=public.release_repair_device_custody(f.org_id,f.case_id,'Workshop',f.recipient_id,
 'Internal courier','issue-A','handoff-proof',2,v_key);
 if public.release_repair_device_custody(f.org_id,f.case_id,'Workshop',f.recipient_id,
 'Internal courier','issue-A','handoff-proof',2,v_key)<>v_response then raise exception 'Release retry changed result'; end if;
 v_transfer:=(v_response->>'transferId')::uuid;
 if (select device_location from public.repair_cases where id=f.case_id)<>'Desk A'
 or (select location from public.repair_device_custody_positions where device_id=f.device_id)<>'Desk A'
 then raise exception 'Release changed confirmed location'; end if;
 begin
  perform public.release_repair_device_custody(f.org_id,f.case_id,'Other',f.recipient_id,
  'Courier','issue-B','proof',3,gen_random_uuid());
  raise exception 'Second open transfer accepted';
 exception when unique_violation then
  if sqlerrm<>'CUSTODY_TRANSFER_OPEN' then raise; end if;
 end;
 begin
  perform public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'accepted','receipt-wrong','proof',3,gen_random_uuid());
  raise exception 'Source accepted destination receipt';
 exception when insufficient_privilege then
  if sqlerrm<>'CUSTODY_ACTOR_MISMATCH' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.recipient_id::text,true);
 v_key:=gen_random_uuid();
 v_response:=public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'accepted','receipt-A','arrival-proof',3,v_key);
 if public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'accepted','receipt-A','arrival-proof',3,v_key)<>v_response
 then raise exception 'Acceptance retry changed result'; end if;
 if (select device_location from public.repair_cases where id=f.case_id)<>'Workshop'
 or (select location from public.repair_device_custody_positions where device_id=f.device_id)<>'Workshop'
 or (select custodian_user_id from public.repair_device_custody_positions where device_id=f.device_id)<>f.recipient_id
 then raise exception 'Acceptance failed to update confirmed position'; end if;
 v_transfer:=(public.release_repair_device_custody(f.org_id,f.case_id,'Desk A',f.sender_id,
 'Return courier','issue-return','return-proof',4,gen_random_uuid())->>'transferId')::uuid;
 perform set_config('request.jwt.claim.sub',f.recipient_id::text,true);
 perform public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'returned','back-to-source','source-proof',5,gen_random_uuid());
 if (select location from public.repair_device_custody_positions where device_id=f.device_id)<>'Workshop'
 then raise exception 'Return changed confirmed position'; end if;
 begin
  update public.repair_device_custody_positions set location='tampered' where device_id=f.device_id;
  raise exception 'Direct custody update allowed';
 exception when insufficient_privilege then null;
 end;
end; $$;
rollback;
