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
            foreignKeyName: "attendance_logs_event_type_id_fkey"
            columns: ["event_type_id"]
            isOneToOne: false
            referencedRelation: "attendance_event_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_logs_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_logs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
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
            foreignKeyName: "leave_requests_leave_type_id_fkey"
            columns: ["leave_type_id"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
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
          invited_by: string | null
          manager_id: string | null
          org_id: string
          role_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          invited_by?: string | null
          manager_id?: string | null
          org_id: string
          role_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          invited_by?: string | null
          manager_id?: string | null
          org_id?: string
          role_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_members_manager_id_fkey"
            columns: ["manager_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_members_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_members_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
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
          name: string
          org_id: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_system?: boolean
          name: string
          org_id: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_system?: boolean
          name?: string
          org_id?: string
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
          created_at: string
          created_by: string
          deleted_at: string | null
          end_time: string
          id: string
          member_id: string
          note: string | null
          org_id: string
          shift_template_id: string | null
          start_time: string
          title: string
          work_date: string
        }
        Insert: {
          created_at?: string
          created_by: string
          deleted_at?: string | null
          end_time: string
          id?: string
          member_id: string
          note?: string | null
          org_id: string
          shift_template_id?: string | null
          start_time: string
          title: string
          work_date: string
        }
        Update: {
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          end_time?: string
          id?: string
          member_id?: string
          note?: string | null
          org_id?: string
          shift_template_id?: string | null
          start_time?: string
          title?: string
          work_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_assignments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_assignments_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_assignments_shift_template_id_fkey"
            columns: ["shift_template_id"]
            isOneToOne: false
            referencedRelation: "shift_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_templates: {
        Row: {
          created_at: string
          deleted_at: string | null
          end_time: string
          id: string
          name: string
          org_id: string
          start_time: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          end_time: string
          id?: string
          name: string
          org_id: string
          start_time: string
        }
        Update: {
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
            foreignKeyName: "tickets_form_template_id_fkey"
            columns: ["form_template_id"]
            isOneToOne: false
            referencedRelation: "form_templates"
            referencedColumns: ["id"]
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

