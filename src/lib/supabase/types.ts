export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      attendance_event_types: {
        Row: {
          created_at: string
          deleted_at: string | null
          id: string
          is_system: boolean
          kind: string
          name: string
          org_id: string
          toggle: boolean
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_system?: boolean
          kind?: string
          name: string
          org_id: string
          toggle?: boolean
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_system?: boolean
          kind?: string
          name?: string
          org_id?: string
          toggle?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "attendance_event_types_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_logs: {
        Row: {
          created_at: string
          created_by: string
          event_type_id: string
          id: string
          member_id: string
          note: string | null
          occurred_at: string
          org_id: string
          voided_at: string | null
          voided_by: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          event_type_id: string
          id?: string
          member_id: string
          note?: string | null
          occurred_at?: string
          org_id: string
          voided_at?: string | null
          voided_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          event_type_id?: string
          id?: string
          member_id?: string
          note?: string | null
          occurred_at?: string
          org_id?: string
          voided_at?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "attendance_logs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_member_same_org"
            columns: ["org_id", "member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "attendance_type_same_org"
            columns: ["org_id", "event_type_id"]
            isOneToOne: false
            referencedRelation: "attendance_event_types"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      audit_log: {
        Row: {
          acted_at: string
          action: string
          actor_id: string | null
          field_name: string | null
          id: string
          new_value: string | null
          note: string | null
          old_value: string | null
          org_id: string
          record_id: string
          table_name: string
        }
        Insert: {
          acted_at?: string
          action?: string
          actor_id?: string | null
          field_name?: string | null
          id?: string
          new_value?: string | null
          note?: string | null
          old_value?: string | null
          org_id: string
          record_id: string
          table_name: string
        }
        Update: {
          acted_at?: string
          action?: string
          actor_id?: string | null
          field_name?: string | null
          id?: string
          new_value?: string | null
          note?: string | null
          old_value?: string | null
          org_id?: string
          record_id?: string
          table_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      calendar_day_status: {
        Row: {
          created_at: string
          created_by: string
          gregorian_date: string
          id: string
          note: string | null
          org_id: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          gregorian_date: string
          id?: string
          note?: string | null
          org_id: string
          status: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          gregorian_date?: string
          id?: string
          note?: string | null
          org_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "calendar_day_status_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      calendar_events: {
        Row: {
          gregorian_date: string
          id: string
          is_holiday: boolean
          jalali_day: number
          jalali_month: number
          jalali_year: number
          title: string
        }
        Insert: {
          gregorian_date: string
          id?: string
          is_holiday?: boolean
          jalali_day: number
          jalali_month: number
          jalali_year: number
          title: string
        }
        Update: {
          gregorian_date?: string
          id?: string
          is_holiday?: boolean
          jalali_day?: number
          jalali_month?: number
          jalali_year?: number
          title?: string
        }
        Relationships: []
      }
      delegations: {
        Row: {
          created_at: string
          created_by: string
          delegate_member_id: string
          delegator_member_id: string
          deleted_at: string | null
          ends_at: string
          id: string
          note: string | null
          org_id: string
          revoked_at: string | null
          starts_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          delegate_member_id: string
          delegator_member_id: string
          deleted_at?: string | null
          ends_at: string
          id?: string
          note?: string | null
          org_id: string
          revoked_at?: string | null
          starts_at: string
        }
        Update: {
          created_at?: string
          created_by?: string
          delegate_member_id?: string
          delegator_member_id?: string
          deleted_at?: string | null
          ends_at?: string
          id?: string
          note?: string | null
          org_id?: string
          revoked_at?: string | null
          starts_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "delegations_delegate_member_id_fkey"
            columns: ["delegate_member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delegations_delegator_member_id_fkey"
            columns: ["delegator_member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delegations_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      fixed_work_schedules: {
        Row: {
          created_at: string
          deleted_at: string | null
          end_time: string
          id: string
          member_id: string
          org_id: string
          start_time: string
          valid_from: string
          valid_to: string | null
          weekday: number
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          end_time: string
          id?: string
          member_id: string
          org_id: string
          start_time: string
          valid_from?: string
          valid_to?: string | null
          weekday: number
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          end_time?: string
          id?: string
          member_id?: string
          org_id?: string
          start_time?: string
          valid_from?: string
          valid_to?: string | null
          weekday?: number
        }
        Relationships: [
          {
            foreignKeyName: "fixed_work_schedules_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_work_schedules_org_id_member_id_fkey"
            columns: ["org_id", "member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      form_fields: {
        Row: {
          created_at: string
          deleted_at: string | null
          field_type: string
          form_template_id: string
          id: string
          is_required: boolean
          key: string
          label: string
          options: Json | null
          sort_order: number
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          field_type: string
          form_template_id: string
          id?: string
          is_required?: boolean
          key: string
          label: string
          options?: Json | null
          sort_order?: number
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          field_type?: string
          form_template_id?: string
          id?: string
          is_required?: boolean
          key?: string
          label?: string
          options?: Json | null
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "form_fields_form_template_id_fkey"
            columns: ["form_template_id"]
            isOneToOne: false
            referencedRelation: "form_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      form_templates: {
        Row: {
          created_at: string
          created_by: string
          deleted_at: string | null
          id: string
          is_active: boolean
          name: string
          org_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          deleted_at?: string | null
          id?: string
          is_active?: boolean
          name: string
          org_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          id?: string
          is_active?: boolean
          name?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "form_templates_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leave_requests: {
        Row: {
          created_at: string
          created_by: string
          deleted_at: string | null
          ends_at: string
          id: string
          leave_type_id: string
          member_id: string
          note: string | null
          org_id: string
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          starts_at: string
          status: string
          tracking_code: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          deleted_at?: string | null
          ends_at: string
          id?: string
          leave_type_id: string
          member_id: string
          note?: string | null
          org_id: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          starts_at: string
          status?: string
          tracking_code?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          ends_at?: string
          id?: string
          leave_type_id?: string
          member_id?: string
          note?: string | null
          org_id?: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          starts_at?: string
          status?: string
          tracking_code?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_member_same_org"
            columns: ["org_id", "member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "leave_requests_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_type_same_org"
            columns: ["org_id", "leave_type_id"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      leave_types: {
        Row: {
          created_at: string
          deleted_at: string | null
          id: string
          name: string
          org_id: string
          unit: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          name: string
          org_id: string
          unit?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          name?: string
          org_id?: string
          unit?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_types_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      org_members: {
        Row: {
          created_at: string
          deleted_at: string | null
          id: string
          invitation_status: string
          invited_by: string | null
          manager_id: string | null
          org_id: string
          role_id: string
          user_id: string
          work_mode: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          invitation_status?: string
          invited_by?: string | null
          manager_id?: string | null
          org_id: string
          role_id: string
          user_id: string
          work_mode?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          invitation_status?: string
          invited_by?: string | null
          manager_id?: string | null
          org_id?: string
          role_id?: string
          user_id?: string
          work_mode?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_members_manager_same_org"
            columns: ["org_id", "manager_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "org_members_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_members_role_same_org"
            columns: ["org_id", "role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "org_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          created_by: string
          deleted_at: string | null
          id: string
          name: string
        }
        Insert: {
          created_at?: string
          created_by: string
          deleted_at?: string | null
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          id?: string
          name?: string
        }
        Relationships: []
      }
      permissions: {
        Row: {
          description_fa: string | null
          key: string
          label_fa: string
          scope_options: string[]
        }
        Insert: {
          description_fa?: string | null
          key: string
          label_fa: string
          scope_options?: string[]
        }
        Update: {
          description_fa?: string | null
          key?: string
          label_fa?: string
          scope_options?: string[]
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          deleted_at: string | null
          email: string
          full_name: string | null
          id: string
          phone: string | null
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          email: string
          full_name?: string | null
          id: string
          phone?: string | null
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          email?: string
          full_name?: string | null
          id?: string
          phone?: string | null
        }
        Relationships: []
      }
      repair_action_plans: {
        Row: {
          amount_irr: number
          case_id: string
          created_at: string
          created_by: string
          diagnosis_id: string
          financial_basis: string
          id: string
          org_id: string
          original_disposition: string | null
          parts_strategy: string | null
          replacement_model: string | null
          replacement_reason: string | null
          revision: number
          route: string
          scope: string
        }
        Insert: {
          amount_irr: number
          case_id: string
          created_at?: string
          created_by: string
          diagnosis_id: string
          financial_basis: string
          id?: string
          org_id: string
          original_disposition?: string | null
          parts_strategy?: string | null
          replacement_model?: string | null
          replacement_reason?: string | null
          revision: number
          route: string
          scope: string
        }
        Update: {
          amount_irr?: number
          case_id?: string
          created_at?: string
          created_by?: string
          diagnosis_id?: string
          financial_basis?: string
          id?: string
          org_id?: string
          original_disposition?: string | null
          parts_strategy?: string | null
          replacement_model?: string | null
          replacement_reason?: string | null
          revision?: number
          route?: string
          scope?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_action_plans_org_id_case_id_diagnosis_id_fkey"
            columns: ["org_id", "case_id", "diagnosis_id"]
            isOneToOne: false
            referencedRelation: "repair_diagnoses"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_action_plans_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_case_assignment_periods: {
        Row: {
          assignee_id: string
          case_id: string
          ended_at: string | null
          id: string
          org_id: string
          request_id: string | null
          started_at: string
        }
        Insert: {
          assignee_id: string
          case_id: string
          ended_at?: string | null
          id?: string
          org_id: string
          request_id?: string | null
          started_at?: string
        }
        Update: {
          assignee_id?: string
          case_id?: string
          ended_at?: string | null
          id?: string
          org_id?: string
          request_id?: string | null
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_case_assignment_period_request_fk"
            columns: ["org_id", "case_id", "request_id"]
            isOneToOne: false
            referencedRelation: "repair_case_assignment_requests"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_case_assignment_periods_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_case_assignment_requests: {
        Row: {
          case_id: string
          from_user_id: string
          id: string
          org_id: string
          request_reference: string
          requested_at: string
          requested_by: string
          resolution_reason: string | null
          resolution_reference: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: string
          target_user_id: string
        }
        Insert: {
          case_id: string
          from_user_id: string
          id?: string
          org_id: string
          request_reference: string
          requested_at?: string
          requested_by: string
          resolution_reason?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          target_user_id: string
        }
        Update: {
          case_id?: string
          from_user_id?: string
          id?: string
          org_id?: string
          request_reference?: string
          requested_at?: string
          requested_by?: string
          resolution_reason?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          target_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_case_assignment_requests_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_case_events: {
        Row: {
          actor_id: string
          case_id: string
          details: Json
          event_type: string
          id: string
          occurred_at: string
          org_id: string
        }
        Insert: {
          actor_id: string
          case_id: string
          details?: Json
          event_type: string
          id?: string
          occurred_at?: string
          org_id: string
        }
        Update: {
          actor_id?: string
          case_id?: string
          details?: Json
          event_type?: string
          id?: string
          occurred_at?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_case_events_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_cases: {
        Row: {
          assigned_to: string
          closed_at: string | null
          created_at: string
          created_by: string
          custody_damage_epoch: number
          customer_name: string
          device_custodian: string | null
          device_location: string | null
          device_model: string
          duplicate_exception_reason: string | null
          duplicate_exception_reference: string | null
          id: string
          imei_evidence: string | null
          imei_verified_at: string | null
          imei_verified_by: string | null
          issue: string
          org_id: string
          priority: string
          raw_identifier: string | null
          receipt_items: string | null
          receipt_method: string | null
          received_at: string | null
          source: string
          stage: string
          stage_entered_at: string
          tracking_code: string | null
          verified_device_id: string | null
          version: number
        }
        Insert: {
          assigned_to: string
          closed_at?: string | null
          created_at?: string
          created_by: string
          custody_damage_epoch?: number
          customer_name: string
          device_custodian?: string | null
          device_location?: string | null
          device_model: string
          duplicate_exception_reason?: string | null
          duplicate_exception_reference?: string | null
          id?: string
          imei_evidence?: string | null
          imei_verified_at?: string | null
          imei_verified_by?: string | null
          issue: string
          org_id: string
          priority: string
          raw_identifier?: string | null
          receipt_items?: string | null
          receipt_method?: string | null
          received_at?: string | null
          source: string
          stage?: string
          stage_entered_at?: string
          tracking_code?: string | null
          verified_device_id?: string | null
          version?: number
        }
        Update: {
          assigned_to?: string
          closed_at?: string | null
          created_at?: string
          created_by?: string
          custody_damage_epoch?: number
          customer_name?: string
          device_custodian?: string | null
          device_location?: string | null
          device_model?: string
          duplicate_exception_reason?: string | null
          duplicate_exception_reference?: string | null
          id?: string
          imei_evidence?: string | null
          imei_verified_at?: string | null
          imei_verified_by?: string | null
          issue?: string
          org_id?: string
          priority?: string
          raw_identifier?: string | null
          receipt_items?: string | null
          receipt_method?: string | null
          received_at?: string | null
          source?: string
          stage?: string
          stage_entered_at?: string
          tracking_code?: string | null
          verified_device_id?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "repair_cases_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "repair_cases_org_id_verified_device_id_fkey"
            columns: ["org_id", "verified_device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_completions: {
        Row: {
          case_id: string
          completed_at: string
          completed_by: string
          device_id: string
          id: string
          org_id: string
          plan_id: string
          protocol_code: string
          repair_stage_entered_at: string
          work_description: string | null
          work_reference: string | null
        }
        Insert: {
          case_id: string
          completed_at?: string
          completed_by: string
          device_id: string
          id?: string
          org_id: string
          plan_id: string
          protocol_code: string
          repair_stage_entered_at: string
          work_description?: string | null
          work_reference?: string | null
        }
        Update: {
          case_id?: string
          completed_at?: string
          completed_by?: string
          device_id?: string
          id?: string
          org_id?: string
          plan_id?: string
          protocol_code?: string
          repair_stage_entered_at?: string
          work_description?: string | null
          work_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "repair_completions_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_completions_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_completions_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_delivery_dispatch_returns: {
        Row: {
          case_id: string
          condition_note: string
          device_id: string
          dispatch_id: string
          id: string
          incident_id: string
          location: string
          org_id: string
          received_at: string
          received_by: string
          return_evidence: string
          return_reference: string
        }
        Insert: {
          case_id: string
          condition_note: string
          device_id: string
          dispatch_id: string
          id?: string
          incident_id: string
          location: string
          org_id: string
          received_at?: string
          received_by: string
          return_evidence: string
          return_reference: string
        }
        Update: {
          case_id?: string
          condition_note?: string
          device_id?: string
          dispatch_id?: string
          id?: string
          incident_id?: string
          location?: string
          org_id?: string
          received_at?: string
          received_by?: string
          return_evidence?: string
          return_reference?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_delivery_dispatch_return_org_id_case_id_dispatch_id_fkey"
            columns: ["org_id", "case_id", "dispatch_id"]
            isOneToOne: false
            referencedRelation: "repair_delivery_dispatches"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_dispatch_return_org_id_case_id_incident_id_fkey"
            columns: ["org_id", "case_id", "incident_id"]
            isOneToOne: false
            referencedRelation: "repair_delivery_incidents"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_dispatch_returns_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_dispatch_returns_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_delivery_dispatches: {
        Row: {
          authority_reference: string | null
          carrier: string
          case_id: string
          destination_address: string
          destination_name: string
          destination_role: string
          device_id: string
          dispatch_evidence: string
          dispatch_reference: string
          dispatched_at: string
          dispatched_by: string
          id: string
          method: string
          org_id: string
          outgoing_check_id: string | null
          repair_outgoing_check_id: string | null
          status: string
          tracking_code: string
        }
        Insert: {
          authority_reference?: string | null
          carrier: string
          case_id: string
          destination_address: string
          destination_name: string
          destination_role: string
          device_id: string
          dispatch_evidence: string
          dispatch_reference: string
          dispatched_at?: string
          dispatched_by: string
          id?: string
          method: string
          org_id: string
          outgoing_check_id?: string | null
          repair_outgoing_check_id?: string | null
          status?: string
          tracking_code: string
        }
        Update: {
          authority_reference?: string | null
          carrier?: string
          case_id?: string
          destination_address?: string
          destination_name?: string
          destination_role?: string
          device_id?: string
          dispatch_evidence?: string
          dispatch_reference?: string
          dispatched_at?: string
          dispatched_by?: string
          id?: string
          method?: string
          org_id?: string
          outgoing_check_id?: string | null
          repair_outgoing_check_id?: string | null
          status?: string
          tracking_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_delivery_dispatches_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_dispatches_org_id_case_id_outgoing_check_i_fkey"
            columns: ["org_id", "case_id", "outgoing_check_id"]
            isOneToOne: false
            referencedRelation: "repair_return_outgoing_checks"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_dispatch_repair_check_fkey"
            columns: ["org_id", "case_id", "repair_outgoing_check_id"]
            isOneToOne: false
            referencedRelation: "repair_outgoing_checks"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_dispatches_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_delivery_incident_followups: {
        Row: {
          case_id: string
          id: string
          incident_id: string
          incident_version: number
          next_due_at: string
          next_responsible_user_id: string
          org_id: string
          outcome: string
          recorded_at: string
          recorded_by: string
          reference: string
        }
        Insert: {
          case_id: string
          id?: string
          incident_id: string
          incident_version: number
          next_due_at: string
          next_responsible_user_id: string
          org_id: string
          outcome: string
          recorded_at?: string
          recorded_by: string
          reference: string
        }
        Update: {
          case_id?: string
          id?: string
          incident_id?: string
          incident_version?: number
          next_due_at?: string
          next_responsible_user_id?: string
          org_id?: string
          outcome?: string
          recorded_at?: string
          recorded_by?: string
          reference?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_delivery_incident_follow_org_id_case_id_incident_id_fkey"
            columns: ["org_id", "case_id", "incident_id"]
            isOneToOne: false
            referencedRelation: "repair_delivery_incidents"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      repair_delivery_incidents: {
        Row: {
          case_id: string
          device_id: string
          dispatch_id: string
          due_at: string
          evidence: string
          id: string
          kind: string
          org_id: string
          recorded_at: string
          recorded_by: string
          reference: string
          resolution_evidence: string | null
          resolution_reference: string | null
          resolved_at: string | null
          resolved_by: string | null
          responsible_user_id: string
          status: string
          version: number
        }
        Insert: {
          case_id: string
          device_id: string
          dispatch_id: string
          due_at: string
          evidence: string
          id?: string
          kind: string
          org_id: string
          recorded_at?: string
          recorded_by: string
          reference: string
          resolution_evidence?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          responsible_user_id: string
          status?: string
          version?: number
        }
        Update: {
          case_id?: string
          device_id?: string
          dispatch_id?: string
          due_at?: string
          evidence?: string
          id?: string
          kind?: string
          org_id?: string
          recorded_at?: string
          recorded_by?: string
          reference?: string
          resolution_evidence?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          responsible_user_id?: string
          status?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "repair_delivery_incidents_org_id_case_id_dispatch_id_fkey"
            columns: ["org_id", "case_id", "dispatch_id"]
            isOneToOne: false
            referencedRelation: "repair_delivery_dispatches"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_incidents_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_incidents_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_delivery_receipts: {
        Row: {
          authority_reference: string | null
          case_id: string
          confirmed_by: string | null
          device_id: string
          dispatch_id: string | null
          handed_over_by: string
          id: string
          method: string
          org_id: string
          outgoing_check_id: string | null
          repair_outgoing_check_id: string | null
          receipt_evidence: string
          receipt_reference: string
          received_at: string
          recipient_name: string
          recipient_role: string
        }
        Insert: {
          authority_reference?: string | null
          case_id: string
          confirmed_by?: string | null
          device_id: string
          dispatch_id?: string | null
          handed_over_by: string
          id?: string
          method: string
          org_id: string
          outgoing_check_id?: string | null
          repair_outgoing_check_id?: string | null
          receipt_evidence: string
          receipt_reference: string
          received_at?: string
          recipient_name: string
          recipient_role: string
        }
        Update: {
          authority_reference?: string | null
          case_id?: string
          confirmed_by?: string | null
          device_id?: string
          dispatch_id?: string | null
          handed_over_by?: string
          id?: string
          method?: string
          org_id?: string
          outgoing_check_id?: string | null
          repair_outgoing_check_id?: string | null
          receipt_evidence?: string
          receipt_reference?: string
          received_at?: string
          recipient_name?: string
          recipient_role?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_delivery_receipts_dispatch_fkey"
            columns: ["org_id", "case_id", "dispatch_id"]
            isOneToOne: false
            referencedRelation: "repair_delivery_dispatches"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_receipts_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: true
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_receipts_org_id_case_id_outgoing_check_id_fkey"
            columns: ["org_id", "case_id", "outgoing_check_id"]
            isOneToOne: false
            referencedRelation: "repair_return_outgoing_checks"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_delivery_receipts_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_device_custody_discrepancies: {
        Row: {
          case_id: string
          device_id: string
          due_at: string
          evidence: string
          id: string
          kind: string
          org_id: string
          recorded_at: string
          recorded_by: string
          reference: string
          resolution_evidence: string | null
          resolution_reference: string | null
          resolved_at: string | null
          resolved_by: string | null
          responsible_user_id: string
          status: string
          transfer_id: string
          version: number
        }
        Insert: {
          case_id: string
          device_id: string
          due_at: string
          evidence: string
          id?: string
          kind: string
          org_id: string
          recorded_at?: string
          recorded_by: string
          reference: string
          resolution_evidence?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          responsible_user_id: string
          status?: string
          transfer_id: string
          version?: number
        }
        Update: {
          case_id?: string
          device_id?: string
          due_at?: string
          evidence?: string
          id?: string
          kind?: string
          org_id?: string
          recorded_at?: string
          recorded_by?: string
          reference?: string
          resolution_evidence?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          responsible_user_id?: string
          status?: string
          transfer_id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "repair_device_custody_discrepancies_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_device_custody_discrepancies_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_device_custody_discrepancies_org_id_transfer_id_fkey"
            columns: ["org_id", "transfer_id"]
            isOneToOne: false
            referencedRelation: "repair_device_custody_transfers"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_device_custody_positions: {
        Row: {
          baseline_evidence: string
          case_id: string
          confirmed_at: string
          confirmed_by: string
          custodian_label: string
          custodian_user_id: string | null
          device_id: string
          external_reference: string | null
          holder_kind: string
          location: string
          org_id: string
        }
        Insert: {
          baseline_evidence: string
          case_id: string
          confirmed_at?: string
          confirmed_by: string
          custodian_label: string
          custodian_user_id?: string | null
          device_id: string
          external_reference?: string | null
          holder_kind?: string
          location: string
          org_id: string
        }
        Update: {
          baseline_evidence?: string
          case_id?: string
          confirmed_at?: string
          confirmed_by?: string
          custodian_label?: string
          custodian_user_id?: string | null
          device_id?: string
          external_reference?: string | null
          holder_kind?: string
          location?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_device_custody_positions_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_device_custody_positions_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: true
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_device_custody_transfers: {
        Row: {
          carrier: string
          case_id: string
          destination_label: string
          destination_location: string
          destination_user_id: string
          device_id: string
          id: string
          org_id: string
          release_evidence: string
          release_reference: string
          released_at: string
          released_by: string
          resolution_evidence: string | null
          resolution_reference: string | null
          resolved_at: string | null
          resolved_by: string | null
          source_custodian_label: string
          source_custodian_user_id: string
          source_location: string
          status: string
          version: number
        }
        Insert: {
          carrier: string
          case_id: string
          destination_label: string
          destination_location: string
          destination_user_id: string
          device_id: string
          id?: string
          org_id: string
          release_evidence: string
          release_reference: string
          released_at?: string
          released_by: string
          resolution_evidence?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_custodian_label: string
          source_custodian_user_id: string
          source_location: string
          status?: string
          version?: number
        }
        Update: {
          carrier?: string
          case_id?: string
          destination_label?: string
          destination_location?: string
          destination_user_id?: string
          device_id?: string
          id?: string
          org_id?: string
          release_evidence?: string
          release_reference?: string
          released_at?: string
          released_by?: string
          resolution_evidence?: string | null
          resolution_reference?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_custodian_label?: string
          source_custodian_user_id?: string
          source_location?: string
          status?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "repair_device_custody_transfers_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_device_custody_transfers_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_devices: {
        Row: {
          first_evidence: string
          first_verified_at: string
          first_verified_by: string
          id: string
          imei: string
          org_id: string
        }
        Insert: {
          first_evidence: string
          first_verified_at?: string
          first_verified_by: string
          id?: string
          imei: string
          org_id: string
        }
        Update: {
          first_evidence?: string
          first_verified_at?: string
          first_verified_by?: string
          id?: string
          imei?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_devices_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      repair_diagnoses: {
        Row: {
          case_id: string
          created_at: string
          created_by: string
          finalized_at: string | null
          finalized_by: string | null
          findings: string
          id: string
          org_id: string
          recommended_action: string
          revision: number
          status: string
          technical_condition: string
          warranty_coverage: string
        }
        Insert: {
          case_id: string
          created_at?: string
          created_by: string
          finalized_at?: string | null
          finalized_by?: string | null
          findings: string
          id?: string
          org_id: string
          recommended_action: string
          revision: number
          status?: string
          technical_condition: string
          warranty_coverage: string
        }
        Update: {
          case_id?: string
          created_at?: string
          created_by?: string
          finalized_at?: string | null
          finalized_by?: string | null
          findings?: string
          id?: string
          org_id?: string
          recommended_action?: string
          revision?: number
          status?: string
          technical_condition?: string
          warranty_coverage?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_diagnoses_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_functional_test_releases: {
        Row: {
          case_id: string
          id: string
          org_id: string
          released_at: string
          released_by: string
          test_id: string
        }
        Insert: {
          case_id: string
          id?: string
          org_id: string
          released_at?: string
          released_by: string
          test_id: string
        }
        Update: {
          case_id?: string
          id?: string
          org_id?: string
          released_at?: string
          released_by?: string
          test_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_functional_test_releases_org_id_case_id_test_id_fkey"
            columns: ["org_id", "case_id", "test_id"]
            isOneToOne: true
            referencedRelation: "repair_functional_tests"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      repair_replacement_executions: {
        Row: {
          id: string; org_id: string; case_id: string; plan_id: string
          original_device_id: string; replacement_device_id: string; allocation_id: string
          replacement_stage_entered_at: string; execution_reference: string; evidence_reference: string
          original_disposition_pending: string; executed_by: string; executed_at: string
        }
        Insert: {
          id?: string; org_id: string; case_id: string; plan_id: string
          original_device_id: string; replacement_device_id: string; allocation_id: string
          replacement_stage_entered_at: string; execution_reference: string; evidence_reference: string
          original_disposition_pending: string; executed_by: string; executed_at?: string
        }
        Update: {
          id?: string; org_id?: string; case_id?: string; plan_id?: string
          original_device_id?: string; replacement_device_id?: string; allocation_id?: string
          replacement_stage_entered_at?: string; execution_reference?: string; evidence_reference?: string
          original_disposition_pending?: string; executed_by?: string; executed_at?: string
        }
        Relationships: []
      }
      repair_functional_tests: {
        Row: {
          case_id: string
          completion_id: string | null
          execution_id: string | null
          configuration_evidence: string
          configuration_status: string
          custody_damage_epoch: number
          device_id: string
          id: string
          identity_evidence: string
          identity_status: string
          org_id: string
          passed: boolean
          plan_id: string
          position_evidence: string
          position_status: string
          power_evidence: string
          power_status: string
          protocol_code: string
          recorded_at: string
          recorded_by: string
          revision: number
        }
        Insert: {
          case_id: string
          completion_id?: string | null
          execution_id?: string | null
          configuration_evidence: string
          configuration_status: string
          custody_damage_epoch: number
          device_id: string
          id?: string
          identity_evidence: string
          identity_status: string
          org_id: string
          passed?: boolean | null
          plan_id: string
          position_evidence: string
          position_status: string
          power_evidence: string
          power_status: string
          protocol_code?: string
          recorded_at?: string
          recorded_by: string
          revision: number
        }
        Update: {
          case_id?: string
          completion_id?: string | null
          execution_id?: string | null
          configuration_evidence?: string
          configuration_status?: string
          custody_damage_epoch?: number
          device_id?: string
          id?: string
          identity_evidence?: string
          identity_status?: string
          org_id?: string
          passed?: boolean | null
          plan_id?: string
          position_evidence?: string
          position_status?: string
          power_evidence?: string
          power_status?: string
          protocol_code?: string
          recorded_at?: string
          recorded_by?: string
          revision?: number
        }
        Relationships: [
          {
            foreignKeyName: "repair_functional_tests_org_id_case_id_completion_id_fkey"
            columns: ["org_id", "case_id", "completion_id"]
            isOneToOne: false
            referencedRelation: "repair_completions"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_functional_tests_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_functional_tests_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_functional_tests_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_outgoing_checks: {
        Row: {
          id: string; org_id: string; case_id: string; plan_id: string; functional_test_id: string
          device_id: string; revision: number; protocol_code: string; custody_damage_epoch: number
          identity_pass: boolean; identity_evidence: string; items_pass: boolean; items_evidence: string
          condition_pass: boolean; condition_evidence: string; transport_pass: boolean; transport_evidence: string
          intended_recipient: string; recipient_role: string; authority_reference: string | null
          recorded_by: string; recorded_at: string
        }
        Insert: {
          id?: string; org_id: string; case_id: string; plan_id: string; functional_test_id: string
          device_id: string; revision: number; protocol_code?: string; custody_damage_epoch: number
          identity_pass: boolean; identity_evidence: string; items_pass: boolean; items_evidence: string
          condition_pass: boolean; condition_evidence: string; transport_pass: boolean; transport_evidence: string
          intended_recipient: string; recipient_role: string; authority_reference?: string | null
          recorded_by: string; recorded_at?: string
        }
        Update: {
          id?: string; org_id?: string; case_id?: string; plan_id?: string; functional_test_id?: string
          device_id?: string; revision?: number; protocol_code?: string; custody_damage_epoch?: number
          identity_pass?: boolean; identity_evidence?: string; items_pass?: boolean; items_evidence?: string
          condition_pass?: boolean; condition_evidence?: string; transport_pass?: boolean; transport_evidence?: string
          intended_recipient?: string; recipient_role?: string; authority_reference?: string | null
          recorded_by?: string; recorded_at?: string
        }
        Relationships: [
          { foreignKeyName: "repair_outgoing_checks_org_id_case_id_fkey"; columns: ["org_id", "case_id"]; isOneToOne: false; referencedRelation: "repair_cases"; referencedColumns: ["org_id", "id"] },
          { foreignKeyName: "repair_outgoing_checks_org_id_case_id_plan_id_fkey"; columns: ["org_id", "case_id", "plan_id"]; isOneToOne: false; referencedRelation: "repair_action_plans"; referencedColumns: ["org_id", "case_id", "id"] },
          { foreignKeyName: "repair_outgoing_checks_org_id_case_id_functional_test_id_fkey"; columns: ["org_id", "case_id", "functional_test_id"]; isOneToOne: false; referencedRelation: "repair_functional_tests"; referencedColumns: ["org_id", "case_id", "id"] },
          { foreignKeyName: "repair_outgoing_checks_org_id_device_id_fkey"; columns: ["org_id", "device_id"]; isOneToOne: false; referencedRelation: "repair_devices"; referencedColumns: ["org_id", "id"] },
        ]
      }
      repair_outgoing_releases: {
        Row: { id: string; org_id: string; case_id: string; check_id: string; released_by: string; released_at: string }
        Insert: { id?: string; org_id: string; case_id: string; check_id: string; released_by: string; released_at?: string }
        Update: { id?: string; org_id?: string; case_id?: string; check_id?: string; released_by?: string; released_at?: string }
        Relationships: [
          { foreignKeyName: "repair_outgoing_releases_org_id_case_id_check_id_fkey"; columns: ["org_id", "case_id", "check_id"]; isOneToOne: true; referencedRelation: "repair_outgoing_checks"; referencedColumns: ["org_id", "case_id", "id"] },
        ]
      }
      repair_part_movements: {
        Row: {
          action_description: string | null
          case_id: string
          id: string
          kind: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          reason: string | null
          recorded_at: string
          recorded_by: string
          reference: string
          reservation_id: string
          source_consumption_id: string | null
        }
        Insert: {
          action_description?: string | null
          case_id: string
          id?: string
          kind: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          reason?: string | null
          recorded_at?: string
          recorded_by: string
          reference: string
          reservation_id: string
          source_consumption_id?: string | null
        }
        Update: {
          action_description?: string | null
          case_id?: string
          id?: string
          kind?: string
          org_id?: string
          part_id?: string
          plan_id?: string
          quantity?: number
          reason?: string | null
          recorded_at?: string
          recorded_by?: string
          reference?: string
          reservation_id?: string
          source_consumption_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "repair_part_movements_org_id_case_id_plan_id_part_id_reser_fkey"
            columns: [
              "org_id",
              "case_id",
              "plan_id",
              "part_id",
              "reservation_id",
            ]
            isOneToOne: false
            referencedRelation: "repair_part_reservations"
            referencedColumns: ["org_id", "case_id", "plan_id", "part_id", "id"]
          },
          {
            foreignKeyName: "repair_part_movements_org_id_case_id_plan_id_part_id_sourc_fkey"
            columns: [
              "org_id",
              "case_id",
              "plan_id",
              "part_id",
              "source_consumption_id",
            ]
            isOneToOne: false
            referencedRelation: "repair_part_movements"
            referencedColumns: ["org_id", "case_id", "plan_id", "part_id", "id"]
          },
        ]
      }
      repair_part_quarantine_resolutions: {
        Row: {
          case_id: string
          decided_at: string
          decided_by: string
          decision_reference: string
          evidence_reference: string
          id: string
          inspection_note: string
          org_id: string
          outcome: string
          part_id: string
          plan_id: string
          quantity: number
          return_movement_id: string
        }
        Insert: {
          case_id: string
          decided_at?: string
          decided_by: string
          decision_reference: string
          evidence_reference: string
          id?: string
          inspection_note: string
          org_id: string
          outcome: string
          part_id: string
          plan_id: string
          quantity: number
          return_movement_id: string
        }
        Update: {
          case_id?: string
          decided_at?: string
          decided_by?: string
          decision_reference?: string
          evidence_reference?: string
          id?: string
          inspection_note?: string
          org_id?: string
          outcome?: string
          part_id?: string
          plan_id?: string
          quantity?: number
          return_movement_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_part_quarantine_resolu_org_id_case_id_plan_id_part__fkey"
            columns: [
              "org_id",
              "case_id",
              "plan_id",
              "part_id",
              "return_movement_id",
            ]
            isOneToOne: false
            referencedRelation: "repair_part_movements"
            referencedColumns: ["org_id", "case_id", "plan_id", "part_id", "id"]
          },
        ]
      }
      repair_part_receipts: {
        Row: {
          evidence_reference: string
          id: string
          org_id: string
          part_id: string
          quantity: number
          recorded_at: string
          recorded_by: string
        }
        Insert: {
          evidence_reference: string
          id?: string
          org_id: string
          part_id: string
          quantity: number
          recorded_at?: string
          recorded_by: string
        }
        Update: {
          evidence_reference?: string
          id?: string
          org_id?: string
          part_id?: string
          quantity?: number
          recorded_at?: string
          recorded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_part_receipts_org_id_part_id_fkey"
            columns: ["org_id", "part_id"]
            isOneToOne: false
            referencedRelation: "repair_parts"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_part_reservation_releases: {
        Row: {
          case_id: string
          id: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          reason: string
          recorded_at: string
          recorded_by: string
          reference: string
          reservation_id: string
        }
        Insert: {
          case_id: string
          id?: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          reason: string
          recorded_at?: string
          recorded_by: string
          reference: string
          reservation_id: string
        }
        Update: {
          case_id?: string
          id?: string
          org_id?: string
          part_id?: string
          plan_id?: string
          quantity?: number
          reason?: string
          recorded_at?: string
          recorded_by?: string
          reference?: string
          reservation_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_part_reservation_relea_org_id_case_id_plan_id_part__fkey"
            columns: [
              "org_id",
              "case_id",
              "plan_id",
              "part_id",
              "reservation_id",
            ]
            isOneToOne: false
            referencedRelation: "repair_part_reservations"
            referencedColumns: ["org_id", "case_id", "plan_id", "part_id", "id"]
          },
        ]
      }
      repair_part_reservations: {
        Row: {
          case_id: string
          consumed_quantity: number
          id: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          released_at: string | null
          reserved_at: string
          reserved_by: string
          status: string
        }
        Insert: {
          case_id: string
          consumed_quantity?: number
          id?: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          released_at?: string | null
          reserved_at?: string
          reserved_by: string
          status?: string
        }
        Update: {
          case_id?: string
          consumed_quantity?: number
          id?: string
          org_id?: string
          part_id?: string
          plan_id?: string
          quantity?: number
          released_at?: string | null
          reserved_at?: string
          reserved_by?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_part_reservations_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_part_reservations_org_id_plan_id_part_id_quantity_fkey"
            columns: ["org_id", "plan_id", "part_id", "quantity"]
            isOneToOne: false
            referencedRelation: "repair_plan_part_requirements"
            referencedColumns: ["org_id", "plan_id", "part_id", "quantity"]
          },
        ]
      }
      repair_parts: {
        Row: {
          active: boolean
          id: string
          name: string
          on_hand: number
          org_id: string
          sku: string
        }
        Insert: {
          active?: boolean
          id?: string
          name: string
          on_hand?: number
          org_id: string
          sku: string
        }
        Update: {
          active?: boolean
          id?: string
          name?: string
          on_hand?: number
          org_id?: string
          sku?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_parts_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      repair_payment_corrections: {
        Row: {
          id: string
          org_id: string
          case_id: string
          payment_id: string
          reason: string
          explanation: string
          correction_reference: string
          evidence_reference: string
          corrected_by: string
          corrected_at: string
        }
        Insert: {
          id?: string
          org_id: string
          case_id: string
          payment_id: string
          reason: string
          explanation: string
          correction_reference: string
          evidence_reference: string
          corrected_by: string
          corrected_at?: string
        }
        Update: {
          id?: string
          org_id?: string
          case_id?: string
          payment_id?: string
          reason?: string
          explanation?: string
          correction_reference?: string
          evidence_reference?: string
          corrected_by?: string
          corrected_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_payment_corrections_org_id_case_id_payment_id_fkey"
            columns: ["org_id", "case_id", "payment_id"]
            isOneToOne: true
            referencedRelation: "repair_payment_evidence"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      repair_payment_evidence: {
        Row: {
          id: string
          org_id: string
          case_id: string
          plan_id: string
          amount_irr: number
          method: string
          external_reference: string
          evidence_reference: string
          recorded_by: string
          recorded_at: string
        }
        Insert: {
          id?: string
          org_id: string
          case_id: string
          plan_id: string
          amount_irr: number
          method: string
          external_reference: string
          evidence_reference: string
          recorded_by: string
          recorded_at?: string
        }
        Update: {
          id?: string
          org_id?: string
          case_id?: string
          plan_id?: string
          amount_irr?: number
          method?: string
          external_reference?: string
          evidence_reference?: string
          recorded_by?: string
          recorded_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_payment_evidence_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      repair_payment_credit_transfers: {
        Row: {
          id: string; org_id: string; case_id: string; source_payment_id: string; target_plan_id: string
          amount_irr: number; request_reference: string; request_evidence: string; requested_by: string
          requested_at: string; approval_reference: string | null; approved_by: string | null; approved_at: string | null
        }
        Insert: {
          id?: string; org_id: string; case_id: string; source_payment_id: string; target_plan_id: string
          amount_irr: number; request_reference: string; request_evidence: string; requested_by: string
          requested_at?: string; approval_reference?: string | null; approved_by?: string | null; approved_at?: string | null
        }
        Update: {
          id?: string; org_id?: string; case_id?: string; source_payment_id?: string; target_plan_id?: string
          amount_irr?: number; request_reference?: string; request_evidence?: string; requested_by?: string
          requested_at?: string; approval_reference?: string | null; approved_by?: string | null; approved_at?: string | null
        }
        Relationships: [
          { foreignKeyName: "repair_payment_credit_transfers_org_id_case_id_source_payment_id_fkey"
            columns: ["org_id", "case_id", "source_payment_id"]; isOneToOne: false
            referencedRelation: "repair_payment_evidence"; referencedColumns: ["org_id", "case_id", "id"] },
          { foreignKeyName: "repair_payment_credit_transfers_org_id_case_id_target_plan_id_fkey"
            columns: ["org_id", "case_id", "target_plan_id"]; isOneToOne: false
            referencedRelation: "repair_action_plans"; referencedColumns: ["org_id", "case_id", "id"] },
        ]
      }
      repair_payment_refunds: {
        Row: {
          id: string; org_id: string; case_id: string; source_payment_id: string; amount_irr: number
          reason: string; request_reference: string; requested_by: string; requested_at: string
          outbound_method: string | null; outbound_reference: string | null; outbound_evidence: string | null
          approval_reference: string | null; approved_by: string | null; approved_at: string | null
        }
        Insert: {
          id?: string; org_id: string; case_id: string; source_payment_id: string; amount_irr: number
          reason: string; request_reference: string; requested_by: string; requested_at?: string
          outbound_method?: string | null; outbound_reference?: string | null; outbound_evidence?: string | null
          approval_reference?: string | null; approved_by?: string | null; approved_at?: string | null
        }
        Update: {
          id?: string; org_id?: string; case_id?: string; source_payment_id?: string; amount_irr?: number
          reason?: string; request_reference?: string; requested_by?: string; requested_at?: string
          outbound_method?: string | null; outbound_reference?: string | null; outbound_evidence?: string | null
          approval_reference?: string | null; approved_by?: string | null; approved_at?: string | null
        }
        Relationships: [
          { foreignKeyName: "repair_payment_refunds_org_id_case_id_source_payment_id_fkey"
            columns: ["org_id", "case_id", "source_payment_id"]; isOneToOne: false
            referencedRelation: "repair_payment_evidence"; referencedColumns: ["org_id", "case_id", "id"] },
        ]
      }
      repair_payment_verifications: {
        Row: {
          id: string
          org_id: string
          case_id: string
          payment_id: string
          verification_reference: string
          verified_by: string
          verified_at: string
        }
        Insert: {
          id?: string
          org_id: string
          case_id: string
          payment_id: string
          verification_reference: string
          verified_by: string
          verified_at?: string
        }
        Update: {
          id?: string
          org_id?: string
          case_id?: string
          payment_id?: string
          verification_reference?: string
          verified_by?: string
          verified_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_payment_verifications_org_id_case_id_payment_id_fkey"
            columns: ["org_id", "case_id", "payment_id"]
            isOneToOne: true
            referencedRelation: "repair_payment_evidence"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      repair_plan_approvals: {
        Row: {
          authority_reference: string | null
          case_id: string
          channel: string | null
          decision: string
          evidence_reference: string | null
          id: string
          kind: string
          org_id: string
          plan_id: string
          recorded_at: string
          recorded_by: string
          stated_at: string | null
          subject_name: string | null
          subject_role: string | null
        }
        Insert: {
          authority_reference?: string | null
          case_id: string
          channel?: string | null
          decision: string
          evidence_reference?: string | null
          id?: string
          kind: string
          org_id: string
          plan_id: string
          recorded_at?: string
          recorded_by: string
          stated_at?: string | null
          subject_name?: string | null
          subject_role?: string | null
        }
        Update: {
          authority_reference?: string | null
          case_id?: string
          channel?: string | null
          decision?: string
          evidence_reference?: string | null
          id?: string
          kind?: string
          org_id?: string
          plan_id?: string
          recorded_at?: string
          recorded_by?: string
          stated_at?: string | null
          subject_name?: string | null
          subject_role?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "repair_plan_approvals_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      repair_plan_part_requirements: {
        Row: {
          case_id: string
          id: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          recorded_at: string
          recorded_by: string
        }
        Insert: {
          case_id: string
          id?: string
          org_id: string
          part_id: string
          plan_id: string
          quantity: number
          recorded_at?: string
          recorded_by: string
        }
        Update: {
          case_id?: string
          id?: string
          org_id?: string
          part_id?: string
          plan_id?: string
          quantity?: number
          recorded_at?: string
          recorded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_plan_part_requirements_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_plan_part_requirements_org_id_part_id_fkey"
            columns: ["org_id", "part_id"]
            isOneToOne: false
            referencedRelation: "repair_parts"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_replacement_allocations: {
        Row: {
          allocated_at: string
          allocated_by: string
          allocation_reference: string
          case_id: string
          device_id: string
          id: string
          org_id: string
          plan_id: string
        }
        Insert: {
          allocated_at?: string
          allocated_by: string
          allocation_reference: string
          case_id: string
          device_id: string
          id?: string
          org_id: string
          plan_id: string
        }
        Update: {
          allocated_at?: string
          allocated_by?: string
          allocation_reference?: string
          case_id?: string
          device_id?: string
          id?: string
          org_id?: string
          plan_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_replacement_allocations_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_replacement_allocations_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_replacement_stock"
            referencedColumns: ["org_id", "device_id"]
          },
        ]
      }
      repair_replacement_warehouse_receipts: {
        Row: { id: string; org_id: string; case_id: string; execution_id: string; original_device_id: string;
          transfer_id: string; disposition: string; location: string; received_by: string;
          receipt_reference: string; receipt_evidence: string; condition_note: string; recorded_at: string }
        Insert: { id?: string; org_id: string; case_id: string; execution_id: string; original_device_id: string;
          transfer_id: string; disposition: string; location: string; received_by: string;
          receipt_reference: string; receipt_evidence: string; condition_note: string; recorded_at?: string }
        Update: { condition_note?: string }
        Relationships: []
      }
      repair_replacement_original_returns: {
        Row: {
          id: string; org_id: string; case_id: string; execution_id: string; original_device_id: string;
          recipient_name: string; recipient_role: string; authority_reference: string | null;
          receipt_reference: string; receipt_evidence: string; condition_note: string;
          returned_by: string; returned_at: string;
        }
        Insert: {
          id?: string; org_id: string; case_id: string; execution_id: string; original_device_id: string;
          recipient_name: string; recipient_role: string; authority_reference?: string | null;
          receipt_reference: string; receipt_evidence: string; condition_note: string;
          returned_by: string; returned_at?: string;
        }
        Update: { condition_note?: string }
        Relationships: []
      }
      repair_replacement_stock: {
        Row: {
          issued_receipt_id: string | null
          issued_at: string | null
          allocated_at: string | null
          allocated_case_id: string | null
          allocated_plan_id: string | null
          custodian_label: string
          custodian_user_id: string
          device_id: string
          evidence: string
          location: string
          model: string
          org_id: string
          receipt_reference: string
          received_at: string
          received_by: string
          status: string
        }
        Insert: {
          issued_receipt_id?: string | null
          issued_at?: string | null
          allocated_at?: string | null
          allocated_case_id?: string | null
          allocated_plan_id?: string | null
          custodian_label: string
          custodian_user_id: string
          device_id: string
          evidence: string
          location: string
          model: string
          org_id: string
          receipt_reference: string
          received_at?: string
          received_by: string
          status?: string
        }
        Update: {
          issued_receipt_id?: string | null
          issued_at?: string | null
          allocated_at?: string | null
          allocated_case_id?: string | null
          allocated_plan_id?: string | null
          custodian_label?: string
          custodian_user_id?: string
          device_id?: string
          evidence?: string
          location?: string
          model?: string
          org_id?: string
          receipt_reference?: string
          received_at?: string
          received_by?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_replacement_stock_org_id_allocated_case_id_allocate_fkey"
            columns: ["org_id", "allocated_case_id", "allocated_plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_replacement_stock_org_id_allocated_case_id_fkey"
            columns: ["org_id", "allocated_case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_replacement_stock_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: true
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_return_authorizations: {
        Row: {
          authorized_at: string
          authorized_by: string
          case_id: string
          id: string
          notification_channel: string
          notification_reference: string
          notified_at: string
          notified_person: string
          org_id: string
          plan_id: string
          protocol_code: string
        }
        Insert: {
          authorized_at?: string
          authorized_by: string
          case_id: string
          id?: string
          notification_channel: string
          notification_reference: string
          notified_at: string
          notified_person: string
          org_id: string
          plan_id: string
          protocol_code?: string
        }
        Update: {
          authorized_at?: string
          authorized_by?: string
          case_id?: string
          id?: string
          notification_channel?: string
          notification_reference?: string
          notified_at?: string
          notified_person?: string
          org_id?: string
          plan_id?: string
          protocol_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_return_authorizations_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: true
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      repair_return_outgoing_checks: {
        Row: {
          authority_reference: string | null
          authorization_id: string
          case_id: string
          condition_evidence: string
          condition_pass: boolean
          created_at: string
          custody_damage_epoch: number
          device_id: string
          id: string
          identity_evidence: string
          identity_pass: boolean
          intended_recipient: string
          items_evidence: string
          items_pass: boolean
          org_id: string
          plan_id: string
          protocol_code: string
          recipient_role: string
          recorded_by: string
          revision: number
          transport_evidence: string
          transport_pass: boolean
        }
        Insert: {
          authority_reference?: string | null
          authorization_id: string
          case_id: string
          condition_evidence: string
          condition_pass: boolean
          created_at?: string
          custody_damage_epoch?: number
          device_id: string
          id?: string
          identity_evidence: string
          identity_pass: boolean
          intended_recipient: string
          items_evidence: string
          items_pass: boolean
          org_id: string
          plan_id: string
          protocol_code?: string
          recipient_role: string
          recorded_by: string
          revision: number
          transport_evidence: string
          transport_pass: boolean
        }
        Update: {
          authority_reference?: string | null
          authorization_id?: string
          case_id?: string
          condition_evidence?: string
          condition_pass?: boolean
          created_at?: string
          custody_damage_epoch?: number
          device_id?: string
          id?: string
          identity_evidence?: string
          identity_pass?: boolean
          intended_recipient?: string
          items_evidence?: string
          items_pass?: boolean
          org_id?: string
          plan_id?: string
          protocol_code?: string
          recipient_role?: string
          recorded_by?: string
          revision?: number
          transport_evidence?: string
          transport_pass?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "repair_return_outgoing_checks_org_id_case_id_authorization_fkey"
            columns: ["org_id", "case_id", "authorization_id"]
            isOneToOne: false
            referencedRelation: "repair_return_authorizations"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_return_outgoing_checks_org_id_case_id_fkey"
            columns: ["org_id", "case_id"]
            isOneToOne: false
            referencedRelation: "repair_cases"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "repair_return_outgoing_checks_org_id_case_id_plan_id_fkey"
            columns: ["org_id", "case_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "repair_action_plans"
            referencedColumns: ["org_id", "case_id", "id"]
          },
          {
            foreignKeyName: "repair_return_outgoing_checks_org_id_device_id_fkey"
            columns: ["org_id", "device_id"]
            isOneToOne: false
            referencedRelation: "repair_devices"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      repair_return_outgoing_releases: {
        Row: {
          case_id: string
          check_id: string
          id: string
          org_id: string
          released_at: string
          released_by: string
        }
        Insert: {
          case_id: string
          check_id: string
          id?: string
          org_id: string
          released_at?: string
          released_by: string
        }
        Update: {
          case_id?: string
          check_id?: string
          id?: string
          org_id?: string
          released_at?: string
          released_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "repair_return_outgoing_releases_org_id_case_id_check_id_fkey"
            columns: ["org_id", "case_id", "check_id"]
            isOneToOne: true
            referencedRelation: "repair_return_outgoing_checks"
            referencedColumns: ["org_id", "case_id", "id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          permission_key: string
          role_id: string
          scope: string | null
        }
        Insert: {
          permission_key: string
          role_id: string
          scope?: string | null
        }
        Update: {
          permission_key?: string
          role_id?: string
          scope?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          created_at: string
          deleted_at: string | null
          id: string
          is_system: boolean
          management_rank: number
          manager_invitable: boolean
          name: string
          org_id: string
          system_key: string | null
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_system?: boolean
          management_rank?: number
          manager_invitable?: boolean
          name: string
          org_id: string
          system_key?: string | null
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_system?: boolean
          management_rank?: number
          manager_invitable?: boolean
          name?: string
          org_id?: string
          system_key?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "roles_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_assignments: {
        Row: {
          color_hex: string
          created_at: string
          created_by: string
          deleted_at: string | null
          end_time: string
          id: string
          member_id: string
          note: string | null
          org_id: string
          shift_pattern_id: string | null
          shift_template_id: string | null
          source: string
          start_time: string
          title: string
          work_date: string
        }
        Insert: {
          color_hex?: string
          created_at?: string
          created_by: string
          deleted_at?: string | null
          end_time: string
          id?: string
          member_id: string
          note?: string | null
          org_id: string
          shift_pattern_id?: string | null
          shift_template_id?: string | null
          source?: string
          start_time: string
          title: string
          work_date: string
        }
        Update: {
          color_hex?: string
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          end_time?: string
          id?: string
          member_id?: string
          note?: string | null
          org_id?: string
          shift_pattern_id?: string | null
          shift_template_id?: string | null
          source?: string
          start_time?: string
          title?: string
          work_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_assignment_pattern_org_fk"
            columns: ["org_id", "shift_pattern_id"]
            isOneToOne: false
            referencedRelation: "shift_patterns"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "shift_assignments_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_member_same_org"
            columns: ["org_id", "member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "shifts_template_same_org"
            columns: ["org_id", "shift_template_id"]
            isOneToOne: false
            referencedRelation: "shift_templates"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      shift_pattern_members: {
        Row: {
          member_id: string
          org_id: string
          pattern_id: string
        }
        Insert: {
          member_id: string
          org_id: string
          pattern_id: string
        }
        Update: {
          member_id?: string
          org_id?: string
          pattern_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_pattern_members_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_pattern_members_org_id_member_id_fkey"
            columns: ["org_id", "member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "shift_pattern_members_org_id_pattern_id_fkey"
            columns: ["org_id", "pattern_id"]
            isOneToOne: false
            referencedRelation: "shift_patterns"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      shift_patterns: {
        Row: {
          created_at: string
          created_by: string
          deleted_at: string | null
          exclude_fridays: boolean
          exclude_official_holidays: boolean
          exclude_unofficial_holidays: boolean
          id: string
          org_id: string
          shift_template_id: string
          valid_from: string
          valid_to: string | null
          weekdays: number[]
        }
        Insert: {
          created_at?: string
          created_by: string
          deleted_at?: string | null
          exclude_fridays?: boolean
          exclude_official_holidays?: boolean
          exclude_unofficial_holidays?: boolean
          id?: string
          org_id: string
          shift_template_id: string
          valid_from: string
          valid_to?: string | null
          weekdays: number[]
        }
        Update: {
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          exclude_fridays?: boolean
          exclude_official_holidays?: boolean
          exclude_unofficial_holidays?: boolean
          id?: string
          org_id?: string
          shift_template_id?: string
          valid_from?: string
          valid_to?: string | null
          weekdays?: number[]
        }
        Relationships: [
          {
            foreignKeyName: "shift_patterns_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_patterns_org_id_shift_template_id_fkey"
            columns: ["org_id", "shift_template_id"]
            isOneToOne: false
            referencedRelation: "shift_templates"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      shift_templates: {
        Row: {
          color_hex: string
          created_at: string
          deleted_at: string | null
          end_time: string
          id: string
          name: string
          org_id: string
          start_time: string
        }
        Insert: {
          color_hex?: string
          created_at?: string
          deleted_at?: string | null
          end_time: string
          id?: string
          name: string
          org_id: string
          start_time: string
        }
        Update: {
          color_hex?: string
          created_at?: string
          deleted_at?: string | null
          end_time?: string
          id?: string
          name?: string
          org_id?: string
          start_time?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_templates_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      ticket_field_values: {
        Row: {
          created_at: string
          form_field_id: string
          id: string
          ticket_id: string
          updated_at: string
          value: Json | null
        }
        Insert: {
          created_at?: string
          form_field_id: string
          id?: string
          ticket_id: string
          updated_at?: string
          value?: Json | null
        }
        Update: {
          created_at?: string
          form_field_id?: string
          id?: string
          ticket_id?: string
          updated_at?: string
          value?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "ticket_field_values_form_field_id_fkey"
            columns: ["form_field_id"]
            isOneToOne: false
            referencedRelation: "form_fields"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ticket_field_values_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      tickets: {
        Row: {
          created_at: string
          created_by: string
          deleted_at: string | null
          form_template_id: string
          id: string
          org_id: string
          status: string
          title: string | null
          tracking_code: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          deleted_at?: string | null
          form_template_id: string
          id?: string
          org_id: string
          status?: string
          title?: string | null
          tracking_code?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          form_template_id?: string
          id?: string
          org_id?: string
          status?: string
          title?: string | null
          tracking_code?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tickets_form_same_org"
            columns: ["org_id", "form_template_id"]
            isOneToOne: false
            referencedRelation: "form_templates"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "tickets_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tracking_codes: {
        Row: {
          code: string
          created_at: string
          entity_id: string
          entity_type: string
          org_id: string
        }
        Insert: {
          code: string
          created_at?: string
          entity_id: string
          entity_type: string
          org_id: string
        }
        Update: {
          code?: string
          created_at?: string
          entity_id?: string
          entity_type?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tracking_codes_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      allocate_repair_replacement_device: {
        Args: {
          p_allocation_reference: string
          p_case_id: string
          p_device_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_plan_id: string
        }
        Returns: Json
      }
      close_repair_return_case: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
        }
        Returns: Json
      }
      close_repaired_case: {
        Args: { p_case_id: string; p_expected_version: number; p_idempotency_key: string; p_org_id: string }
        Returns: Json
      }
      advance_repaired_case_to_delivery: {
        Args: { p_case_id: string; p_expected_version: number; p_idempotency_key: string; p_org_id: string }
        Returns: Json
      }
      advance_replacement_case_to_delivery: {
        Args: { p_case_id: string; p_expected_version: number; p_idempotency_key: string; p_org_id: string }
        Returns: Json
      }
      complete_repair_for_test: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_protocol_code: string
          p_work_description: string | null
          p_work_reference: string | null
        }
        Returns: Json
      }
      execute_repair_replacement_for_test: {
        Args: {
          p_case_id: string
          p_evidence_reference: string
          p_execution_reference: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
        }
        Returns: Json
      }
      confirm_repair_delivery_receipt: {
        Args: {
          p_authority_reference: string | null
          p_case_id: string
          p_dispatch_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_receipt_evidence: string
          p_receipt_reference: string
          p_recipient_name: string
          p_recipient_role: string
        }
        Returns: Json
      }
      confirm_replacement_delivery_receipt: {
        Args: {
          p_authority_reference: string | null
          p_case_id: string
          p_dispatch_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_receipt_evidence: string
          p_receipt_reference: string
          p_recipient_name: string
          p_recipient_role: string
        }
        Returns: Json
      }
      confirm_repaired_delivery_receipt: {
        Args: {
          p_authority_reference: string | null
          p_case_id: string
          p_dispatch_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_receipt_evidence: string
          p_receipt_reference: string
          p_recipient_name: string
          p_recipient_role: string
        }
        Returns: Json
      }
      consume_repair_part: {
        Args: {
          p_action_description: string
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_part_id: string
          p_plan_id: string
          p_quantity: number
          p_reference: string
        }
        Returns: Json
      }
      create_organization: {
        Args: { p_name: string }
        Returns: {
          created_at: string
          created_by: string
          deleted_at: string | null
          id: string
          name: string
        }
        SetofOptions: {
          from: "*"
          to: "organizations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_repair_case: {
        Args: {
          p_customer_name: string
          p_device_model: string
          p_idempotency_key: string
          p_issue: string
          p_org_id: string
          p_priority: string
          p_raw_identifier: string | null
          p_source: string
        }
        Returns: Json
      }
      create_ticket: {
        Args: {
          p_field_values: Json
          p_form_template_id: string
          p_org_id: string
          p_title: string
        }
        Returns: {
          created_at: string
          created_by: string
          deleted_at: string | null
          form_template_id: string
          id: string
          org_id: string
          status: string
          title: string | null
          tracking_code: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "tickets"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalize_repair_diagnosis: {
        Args: {
          p_case_id: string
          p_diagnosis_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
        }
        Returns: Json
      }
      followup_repair_delivery_incident: {
        Args: {
          p_case_id: string
          p_due_at: string
          p_expected_incident_version: number
          p_expected_version: number
          p_idempotency_key: string
          p_incident_id: string
          p_org_id: string
          p_outcome: string
          p_reference: string
          p_responsible_user_id: string
        }
        Returns: Json
      }
      has_permission: {
        Args: { p_org_id: string; p_permission_key: string }
        Returns: boolean
      }
      is_manager_of: {
        Args: { p_org_id: string; p_target_member_id: string }
        Returns: boolean
      }
      permission_scope: {
        Args: { p_org_id: string; p_permission_key: string }
        Returns: string
      }
      receive_repair_delivery_damage_return: {
        Args: {
          p_case_id: string
          p_condition_note: string
          p_dispatch_id: string
          p_expected_incident_version: number
          p_expected_version: number
          p_idempotency_key: string
          p_incident_id: string
          p_location: string
          p_org_id: string
          p_return_evidence: string
          p_return_reference: string
        }
        Returns: Json
      }
      receive_repair_device: {
        Args: {
          p_case_id: string
          p_custodian: string
          p_duplicate_reason?: string | null
          p_duplicate_reference?: string | null
          p_expected_version: number
          p_idempotency_key: string
          p_imei_evidence?: string | null
          p_items: string
          p_location: string
          p_method: string
          p_org_id: string
          p_verified_imei?: string | null
        }
        Returns: Json
      }
      receive_repair_part: {
        Args: {
          p_evidence_reference: string
          p_idempotency_key: string
          p_name: string
          p_org_id: string
          p_quantity: number
          p_sku: string
        }
        Returns: Json
      }
      receive_repair_replacement_stock: {
        Args: {
          p_custodian_user_id: string
          p_evidence: string
          p_idempotency_key: string
          p_imei: string
          p_location: string
          p_model: string
          p_org_id: string
          p_receipt_reference: string
        }
        Returns: Json
      }
      record_repair_custody_discrepancy: {
        Args: {
          p_case_id: string
          p_due_at: string
          p_evidence: string
          p_expected_transfer_version: number
          p_expected_version: number
          p_idempotency_key: string
          p_kind: string
          p_org_id: string
          p_reference: string
          p_responsible_user_id: string
          p_transfer_id: string
        }
        Returns: Json
      }
      record_repair_delivery_dispatch: {
        Args: {
          p_carrier: string
          p_case_id: string
          p_destination_address: string
          p_dispatch_evidence: string
          p_dispatch_reference: string
          p_expected_version: number
          p_idempotency_key: string
          p_method: string
          p_org_id: string
          p_tracking_code: string
        }
        Returns: Json
      }
      record_replacement_delivery_dispatch: {
        Args: {
          p_carrier: string
          p_case_id: string
          p_destination_address: string
          p_dispatch_evidence: string
          p_dispatch_reference: string
          p_expected_version: number
          p_idempotency_key: string
          p_method: string
          p_org_id: string
          p_tracking_code: string
        }
        Returns: Json
      }
      record_repaired_delivery_dispatch: {
        Args: {
          p_carrier: string
          p_case_id: string
          p_destination_address: string
          p_dispatch_evidence: string
          p_dispatch_reference: string
          p_expected_version: number
          p_idempotency_key: string
          p_method: string
          p_org_id: string
          p_tracking_code: string
        }
        Returns: Json
      }
      record_repair_delivery_incident: {
        Args: {
          p_case_id: string
          p_dispatch_id: string
          p_due_at: string
          p_evidence: string
          p_expected_version: number
          p_idempotency_key: string
          p_kind: string
          p_org_id: string
          p_reference: string
          p_responsible_user_id: string
        }
        Returns: Json
      }
      record_repair_delivery_receipt: {
        Args: {
          p_authority_reference: string | null
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_receipt_evidence: string
          p_receipt_reference: string
          p_recipient_name: string
          p_recipient_role: string
        }
        Returns: Json
      }
      record_repaired_delivery_receipt: {
        Args: {
          p_authority_reference: string | null
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_receipt_evidence: string
          p_receipt_reference: string
          p_recipient_name: string
          p_recipient_role: string
        }
        Returns: Json
      }
      record_replacement_warehouse_receipt: {
        Args: { p_org_id: string; p_case_id: string; p_transfer_id: string; p_expected_version: number;
          p_idempotency_key: string; p_condition_note: string }
        Returns: Json
      }
      record_replacement_original_return: {
        Args: { p_org_id: string; p_case_id: string; p_expected_version: number; p_idempotency_key: string;
          p_receipt_reference: string; p_receipt_evidence: string; p_condition_note: string }
        Returns: Json
      }
      close_replacement_case: {
        Args: { p_org_id: string; p_case_id: string; p_expected_version: number; p_idempotency_key: string }
        Returns: Json
      }
      record_replacement_delivery_receipt: {
        Args: {
          p_authority_reference: string | null
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_receipt_evidence: string
          p_receipt_reference: string
          p_recipient_name: string
          p_recipient_role: string
        }
        Returns: Json
      }
      record_repair_device_custody_baseline: {
        Args: {
          p_case_id: string
          p_custodian_user_id: string
          p_evidence: string
          p_expected_version: number
          p_idempotency_key: string
          p_location: string
          p_org_id: string
        }
        Returns: Json
      }
      record_repair_functional_test: {
        Args: {
          p_case_id: string
          p_configuration_evidence: string
          p_configuration_status: string
          p_expected_version: number
          p_idempotency_key: string
          p_identity_evidence: string
          p_identity_status: string
          p_org_id: string
          p_position_evidence: string
          p_position_status: string
          p_power_evidence: string
          p_power_status: string
        }
        Returns: Json
      }
      record_repair_replacement_functional_test: {
        Args: {
          p_case_id: string
          p_configuration_evidence: string
          p_configuration_status: string
          p_expected_version: number
          p_idempotency_key: string
          p_identity_evidence: string
          p_identity_status: string
          p_org_id: string
          p_position_evidence: string
          p_position_status: string
          p_power_evidence: string
          p_power_status: string
        }
        Returns: Json
      }
      correct_repair_payment_evidence: {
        Args: {
          p_org_id: string
          p_case_id: string
          p_payment_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_reason: string
          p_explanation: string
          p_correction_reference: string
          p_evidence_reference: string
        }
        Returns: Json
      }
      request_repair_payment_credit_transfer: {
        Args: {
          p_org_id: string; p_case_id: string; p_source_payment_id: string; p_expected_version: number
          p_idempotency_key: string; p_amount_irr: number; p_request_reference: string; p_request_evidence: string
        }
        Returns: Json
      }
      request_repair_payment_refund: {
        Args: {
          p_org_id: string; p_case_id: string; p_source_payment_id: string; p_expected_version: number
          p_idempotency_key: string; p_amount_irr: number; p_reason: string; p_request_reference: string
        }
        Returns: Json
      }
      approve_repair_payment_refund: {
        Args: {
          p_org_id: string; p_case_id: string; p_refund_id: string; p_expected_version: number
          p_idempotency_key: string; p_outbound_method: string; p_outbound_reference: string
          p_outbound_evidence: string; p_approval_reference: string
        }
        Returns: Json
      }
      approve_repair_payment_credit_transfer: {
        Args: {
          p_org_id: string; p_case_id: string; p_transfer_id: string; p_expected_version: number
          p_idempotency_key: string; p_approval_reference: string
        }
        Returns: Json
      }
      record_repair_payment_evidence: {
        Args: {
          p_org_id: string
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_amount_irr: number
          p_method: string
          p_external_reference: string
          p_evidence_reference: string
        }
        Returns: Json
      }
      record_repair_outgoing_check: {
        Args: {
          p_org_id: string; p_case_id: string; p_expected_version: number; p_idempotency_key: string
          p_identity_pass: boolean; p_identity_evidence: string; p_items_pass: boolean; p_items_evidence: string
          p_condition_pass: boolean; p_condition_evidence: string; p_transport_pass: boolean; p_transport_evidence: string
          p_intended_recipient: string; p_recipient_role: string; p_authority_reference: string | null
        }
        Returns: Json
      }
      record_replacement_outgoing_check: {
        Args: {
          p_org_id: string; p_case_id: string; p_expected_version: number; p_idempotency_key: string
          p_identity_pass: boolean; p_identity_evidence: string; p_items_pass: boolean; p_items_evidence: string
          p_condition_pass: boolean; p_condition_evidence: string; p_transport_pass: boolean; p_transport_evidence: string
          p_intended_recipient: string; p_recipient_role: string; p_authority_reference: string | null
        }
        Returns: Json
      }
      record_repair_plan_approval: {
        Args: {
          p_authority_reference?: string | null
          p_case_id: string
          p_channel?: string | null
          p_decision: string
          p_evidence_reference?: string | null
          p_expected_version: number
          p_idempotency_key: string
          p_kind: string
          p_org_id: string
          p_plan_id: string
          p_stated_at?: string | null
          p_subject_name?: string | null
          p_subject_role?: string | null
        }
        Returns: Json
      }
      record_repair_return_authorization: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_notification_channel: string
          p_notification_reference: string
          p_notified_at: string
          p_notified_person: string
          p_org_id: string
          p_plan_id: string
        }
        Returns: Json
      }
      record_repair_return_outgoing_check: {
        Args: {
          p_authority_reference: string | null
          p_case_id: string
          p_condition_evidence: string
          p_condition_pass: boolean
          p_expected_version: number
          p_idempotency_key: string
          p_identity_evidence: string
          p_identity_pass: boolean
          p_intended_recipient: string
          p_items_evidence: string
          p_items_pass: boolean
          p_org_id: string
          p_recipient_role: string
          p_transport_evidence: string
          p_transport_pass: boolean
        }
        Returns: Json
      }
      verify_repair_payment_evidence: {
        Args: {
          p_org_id: string
          p_case_id: string
          p_payment_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_verification_reference: string
        }
        Returns: Json
      }
      release_repair_device_custody: {
        Args: {
          p_carrier: string
          p_case_id: string
          p_destination_location: string
          p_destination_user_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_release_evidence: string
          p_release_reference: string
        }
        Returns: Json
      }
      release_repair_outgoing_check: {
        Args: { p_org_id: string; p_case_id: string; p_check_id: string; p_expected_version: number; p_idempotency_key: string }
        Returns: Json
      }
      release_repair_functional_test: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_test_id: string
        }
        Returns: Json
      }
      release_repair_replacement_custody: {
        Args: {
          p_carrier: string
          p_case_id: string
          p_destination_location: string
          p_destination_user_id: string
          p_device_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_release_evidence: string
          p_release_reference: string
        }
        Returns: Json
      }
      release_repair_return_outgoing_check: {
        Args: {
          p_case_id: string
          p_check_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
        }
        Returns: Json
      }
      release_unused_repair_part: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_part_id: string
          p_plan_id: string
          p_reason: string
          p_reference: string
        }
        Returns: Json
      }
      request_repair_case_assignment: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_request_reference: string
          p_target_user_id: string
        }
        Returns: Json
      }
      require_repair_part: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_part_id: string
          p_plan_id: string
          p_quantity: number
        }
        Returns: Json
      }
      reserve_repair_part: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_part_id: string
          p_plan_id: string
        }
        Returns: Json
      }
      resolve_repair_case_assignment: {
        Args: {
          p_case_id: string
          p_decision: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_reason: string | null
          p_request_id: string
          p_resolution_reference: string | null
        }
        Returns: Json
      }
      resolve_repair_custody_discrepancy: {
        Args: {
          p_case_id: string
          p_discrepancy_id: string
          p_evidence: string
          p_expected_discrepancy_version: number
          p_expected_transfer_version: number
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_reference: string
        }
        Returns: Json
      }
      resolve_repair_delivery_incident: {
        Args: {
          p_case_id: string
          p_expected_incident_version: number
          p_expected_version: number
          p_idempotency_key: string
          p_incident_id: string
          p_org_id: string
          p_resolution_evidence: string
          p_resolution_reference: string
        }
        Returns: Json
      }
      resolve_repair_device_custody: {
        Args: {
          p_case_id: string
          p_evidence: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_outcome: string
          p_reference: string
          p_transfer_id: string
        }
        Returns: Json
      }
      resolve_repair_part_quarantine: {
        Args: {
          p_case_id: string
          p_decision_reference: string
          p_evidence_reference: string
          p_expected_version: number
          p_idempotency_key: string
          p_inspection_note: string
          p_org_id: string
          p_outcome: string
          p_quantity: number
          p_return_movement_id: string
        }
        Returns: Json
      }
      resolve_repair_replacement_custody: {
        Args: {
          p_case_id: string
          p_evidence: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_outcome: string
          p_reference: string
          p_transfer_id: string
        }
        Returns: Json
      }
      return_consumed_repair_part: {
        Args: {
          p_case_id: string
          p_consumption_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_quantity: number
          p_reason: string
          p_reference: string
        }
        Returns: Json
      }
      return_repair_case_to_test_after_damage: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
        }
        Returns: Json
      }
      save_repair_action_plan: {
        Args: {
          p_amount_irr: number
          p_case_id: string
          p_expected_version: number
          p_financial_basis: string
          p_idempotency_key: string
          p_org_id: string
          p_original_disposition?: string | null
          p_parts_strategy?: string | null
          p_replacement_model?: string | null
          p_replacement_reason?: string | null
          p_route: string
          p_scope: string
        }
        Returns: Json
      }
      save_repair_diagnosis: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_findings: string
          p_idempotency_key: string
          p_org_id: string
          p_recommended_action: string
          p_technical_condition: string
          p_warranty_coverage: string
        }
        Returns: Json
      }
      save_role: {
        Args: {
          p_management_rank: number
          p_name: string
          p_org_id: string
          p_permissions: Json
          p_role_id: string | null
        }
        Returns: string
      }
      set_role_permissions: {
        Args: { p_permissions: Json; p_role_id: string }
        Returns: undefined
      }
      team_leave_calendar: {
        Args: { p_from: string; p_org_id: string; p_to: string }
        Returns: {
          ends_at: string
          leave_type_name: string
          member_id: string
          member_name: string
          starts_at: string
        }[]
      }
      transfer_org_ownership: {
        Args: {
          p_former_owner_role_id: string
          p_org_id: string
          p_successor_member_id: string
        }
        Returns: undefined
      }
      transition_repair_case: {
        Args: {
          p_case_id: string
          p_expected_version: number
          p_idempotency_key: string
          p_org_id: string
          p_transition_code: string
        }
        Returns: Json
      }
      update_ticket_field_value: {
        Args: {
          p_form_field_id: string
          p_note?: string
          p_ticket_id: string
          p_value: Json
        }
        Returns: undefined
      }
      update_ticket_status: {
        Args: { p_note?: string; p_status: string; p_ticket_id: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
