\set ON_ERROR_STOP on
begin;
create temp table discrepancy_fixture as select gen_random_uuid() org_id,gen_random_uuid() sender_id,
 gen_random_uuid() recipient_id,gen_random_uuid() role_id,gen_random_uuid() case_id,
 gen_random_uuid() device_id;
insert into auth.users(id,aud,role,email)
select sender_id,'authenticated','authenticated','discrepancy-source@example.test' from discrepancy_fixture
union all select recipient_id,'authenticated','authenticated','discrepancy-target@example.test' from discrepancy_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Discrepancy test',sender_id from discrepancy_fixture;
insert into public.roles(id,org_id,name,is_system)
select role_id,org_id,'Discrepancy operators',false from discrepancy_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,sender_id,role_id from discrepancy_fixture
union all select org_id,recipient_id,role_id from discrepancy_fixture;
insert into public.role_permissions(role_id,permission_key)
select role_id,key from discrepancy_fixture cross join public.permissions where key in
('repair.case.view','custody.baseline.record','custody.transfer.release','custody.transfer.accept','custody.transfer.return',
'custody.transfer.discrepancy.record','custody.transfer.discrepancy.resolve');
insert into public.repair_devices(id,org_id,imei,first_verified_by,first_evidence)
select device_id,org_id,'123456789012346',sender_id,'label-photo' from discrepancy_fixture;
insert into public.repair_cases(id,org_id,created_by,customer_name,device_model,issue,priority,source,
 received_at,receipt_method,device_location,device_custodian,verified_device_id,imei_evidence,imei_verified_by,imei_verified_at)
select case_id,org_id,sender_id,'Customer','Model','Issue','normal','walk_in',clock_timestamp(),
 'walk_in','Desk A','Operator A',device_id,'label-photo',sender_id,clock_timestamp() from discrepancy_fixture;
grant select on discrepancy_fixture to authenticated;
set local role authenticated;
do $$
declare f record; v_transfer uuid; v_item uuid; v_response jsonb; v_key uuid;
begin
 select * into f from discrepancy_fixture;
 perform set_config('request.jwt.claim.sub',f.sender_id::text,true);
 perform public.record_repair_device_custody_baseline(f.org_id,f.case_id,'Desk A',f.sender_id,'baseline-proof',1,gen_random_uuid());
 v_transfer:=(public.release_repair_device_custody(f.org_id,f.case_id,'Workshop',f.recipient_id,
 'Internal courier','issue-discrepancy-A','handoff-proof',2,gen_random_uuid())->>'transferId')::uuid;
 perform set_config('request.jwt.claim.sub',f.recipient_id::text,true);
 v_key:=gen_random_uuid();
 v_response:=public.record_repair_custody_discrepancy(f.org_id,f.case_id,v_transfer,'identity_mismatch',
 'discrepancy-A','label-diff',f.sender_id,clock_timestamp()+interval '1 day',3,1,v_key);
 if (v_response->>'discrepancyId') is null then raise exception 'Missing discrepancy response'; end if;
 v_item:=(v_response->>'discrepancyId')::uuid;
 if (select version from public.repair_device_custody_transfers where id=v_transfer)<>2 then raise exception 'Transfer version not advanced'; end if;
 begin
  perform public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'accepted','stale-receipt','proof',3,gen_random_uuid());
  raise exception 'Stale receipt accepted';
 exception when raise_exception then
  if sqlerrm<>'CASE_VERSION_CONFLICT' then raise; end if;
 end;
 begin
  perform public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'accepted','blocked-receipt','proof',4,gen_random_uuid());
  raise exception 'Open discrepancy bypassed';
 exception when check_violation then
  if sqlerrm<>'CUSTODY_DISCREPANCY_OPEN' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.sender_id::text,true);
 v_response:=public.resolve_repair_custody_discrepancy(f.org_id,f.case_id,v_item,'resolved-A','verified-label',4,2,1,gen_random_uuid());
 if (v_response->>'version')::integer<>5 then raise exception 'Discrepancy resolution did not advance case'; end if;
 perform set_config('request.jwt.claim.sub',f.recipient_id::text,true);
 begin
  perform public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'accepted','old-after-resolution','proof',4,gen_random_uuid());
  raise exception 'Old receipt accepted after resolution';
 exception when raise_exception then
  if sqlerrm<>'CASE_VERSION_CONFLICT' then raise; end if;
 end;
 perform public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'accepted','fresh-receipt-A','arrival-proof',5,gen_random_uuid());
 if (select location from public.repair_device_custody_positions where device_id=f.device_id)<>'Workshop'
 then raise exception 'Fresh receipt failed'; end if;
 v_transfer:=(public.release_repair_device_custody(f.org_id,f.case_id,'Desk A',f.sender_id,
 'Return courier','issue-discrepancy-B','handoff-proof',6,gen_random_uuid())->>'transferId')::uuid;
 perform set_config('request.jwt.claim.sub',f.sender_id::text,true);
 v_item:=(public.record_repair_custody_discrepancy(f.org_id,f.case_id,v_transfer,'damage',
 'damage-B','damage-photo',f.recipient_id,clock_timestamp()+interval '1 day',7,1,gen_random_uuid())->>'discrepancyId')::uuid;
 begin
  perform public.resolve_repair_custody_discrepancy(f.org_id,f.case_id,v_item,'wrong-damage-resolution','inspection',8,2,1,gen_random_uuid());
  raise exception 'Damage resolved before return';
 exception when check_violation then
  if sqlerrm<>'CUSTODY_DISCREPANCY_RETURN_REQUIRED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.recipient_id::text,true);
 perform public.resolve_repair_device_custody(f.org_id,f.case_id,v_transfer,'returned','return-B','source-proof',8,gen_random_uuid());
 begin
  perform public.release_repair_device_custody(f.org_id,f.case_id,'Other desk',f.sender_id,
  'Courier','issue-before-damage-review','proof',9,gen_random_uuid());
  raise exception 'Release with open damage discrepancy succeeded';
 exception when check_violation then
  if sqlerrm<>'CUSTODY_DISCREPANCY_OPEN' then raise; end if;
 end;
 perform public.resolve_repair_custody_discrepancy(f.org_id,f.case_id,v_item,'damage-reviewed','inspection-ref',9,3,1,gen_random_uuid());
 if (select location from public.repair_device_custody_positions where device_id=f.device_id)<>'Workshop'
 or (select status from public.repair_device_custody_discrepancies where id=v_item)<>'resolved'
 then raise exception 'Damage return altered confirmed position or failed to resolve'; end if;
end; $$;
rollback;
