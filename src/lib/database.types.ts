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
      attendance_records: {
        Row: {
          clock_in_at: string | null
          clock_out_at: string | null
          created_at: string
          early_departure_minutes: number | null
          employee_id: string
          id: string
          late_minutes: number | null
          notes: string | null
          overtime_minutes: number | null
          recorded_by: string | null
          shift_id: string | null
          site_id: string
          status: Database["public"]["Enums"]["attendance_status"]
          tenant_id: string
          updated_at: string
          worked_minutes: number | null
        }
        Insert: {
          clock_in_at?: string | null
          clock_out_at?: string | null
          created_at?: string
          early_departure_minutes?: number | null
          employee_id: string
          id?: string
          late_minutes?: number | null
          notes?: string | null
          overtime_minutes?: number | null
          recorded_by?: string | null
          shift_id?: string | null
          site_id: string
          status?: Database["public"]["Enums"]["attendance_status"]
          tenant_id: string
          updated_at?: string
          worked_minutes?: number | null
        }
        Update: {
          clock_in_at?: string | null
          clock_out_at?: string | null
          created_at?: string
          early_departure_minutes?: number | null
          employee_id?: string
          id?: string
          late_minutes?: number | null
          notes?: string | null
          overtime_minutes?: number | null
          recorded_by?: string | null
          shift_id?: string | null
          site_id?: string
          status?: Database["public"]["Enums"]["attendance_status"]
          tenant_id?: string
          updated_at?: string
          worked_minutes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "attendance_records_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shifts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_policies: {
        Row: {
          created_at: string
          early_departure_threshold_minutes: number
          grace_period_minutes: number
          id: string
          overtime_threshold_minutes: number
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          early_departure_threshold_minutes?: number
          grace_period_minutes?: number
          id?: string
          overtime_threshold_minutes?: number
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          early_departure_threshold_minutes?: number
          grace_period_minutes?: number
          id?: string
          overtime_threshold_minutes?: number
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_policies_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_breaks: {
        Row: {
          attendance_record_id: string
          break_end: string | null
          break_start: string
          created_at: string
          id: string
          tenant_id: string
        }
        Insert: {
          attendance_record_id: string
          break_end?: string | null
          break_start?: string
          created_at?: string
          id?: string
          tenant_id: string
        }
        Update: {
          attendance_record_id?: string
          break_end?: string | null
          break_start?: string
          created_at?: string
          id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_breaks_attendance_record_id_fkey"
            columns: ["attendance_record_id"]
            isOneToOne: false
            referencedRelation: "attendance_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_breaks_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_corrections: {
        Row: {
          attendance_record_id: string
          created_at: string
          field: Database["public"]["Enums"]["attendance_correction_field"]
          id: string
          new_value: string
          previous_value: string | null
          reason: string
          requested_by: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["attendance_correction_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          attendance_record_id: string
          created_at?: string
          field: Database["public"]["Enums"]["attendance_correction_field"]
          id?: string
          new_value: string
          previous_value?: string | null
          reason: string
          requested_by?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["attendance_correction_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          attendance_record_id?: string
          created_at?: string
          field?: Database["public"]["Enums"]["attendance_correction_field"]
          id?: string
          new_value?: string
          previous_value?: string | null
          reason?: string
          requested_by?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["attendance_correction_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_corrections_attendance_record_id_fkey"
            columns: ["attendance_record_id"]
            isOneToOne: false
            referencedRelation: "attendance_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_corrections_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_corrections_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_corrections_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_profile_id: string | null
          after: Json | null
          before: Json | null
          created_at: string
          entity_id: string
          entity_table: string
          id: string
          tenant_id: string | null
        }
        Insert: {
          action: string
          actor_profile_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity_id: string
          entity_table: string
          id?: string
          tenant_id?: string | null
        }
        Update: {
          action?: string
          actor_profile_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity_id?: string
          entity_table?: string
          id?: string
          tenant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_profile_id_fkey"
            columns: ["actor_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_log_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          created_at: string
          id: string
          industry: string | null
          name: string
          primary_contact_email: string | null
          primary_contact_name: string | null
          primary_contact_phone: string | null
          region_id: string | null
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          industry?: string | null
          name: string
          primary_contact_email?: string | null
          primary_contact_name?: string | null
          primary_contact_phone?: string | null
          region_id?: string | null
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          industry?: string | null
          name?: string
          primary_contact_email?: string | null
          primary_contact_name?: string | null
          primary_contact_phone?: string | null
          region_id?: string | null
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clients_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "regions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clients_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      contract_sites: {
        Row: {
          contract_id: string
          created_at: string
          site_id: string
          tenant_id: string
        }
        Insert: {
          contract_id: string
          created_at?: string
          site_id: string
          tenant_id: string
        }
        Update: {
          contract_id?: string
          created_at?: string
          site_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "contract_sites_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "contracts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_sites_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_sites_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      contracts: {
        Row: {
          client_id: string
          contract_number: string
          created_at: string
          end_date: string | null
          id: string
          responsible_manager_id: string | null
          sla_notes: string | null
          start_date: string
          status: Database["public"]["Enums"]["contract_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          client_id: string
          contract_number: string
          created_at?: string
          end_date?: string | null
          id?: string
          responsible_manager_id?: string | null
          sla_notes?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["contract_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          client_id?: string
          contract_number?: string
          created_at?: string
          end_date?: string | null
          id?: string
          responsible_manager_id?: string | null
          sla_notes?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["contract_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contracts_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contracts_responsible_manager_id_fkey"
            columns: ["responsible_manager_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contracts_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      departments: {
        Row: {
          created_at: string
          id: string
          name: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "departments_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_availability: {
        Row: {
          created_at: string
          day_of_week: number
          employee_id: string
          end_time: string
          id: string
          start_time: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          day_of_week: number
          employee_id: string
          end_time: string
          id?: string
          start_time: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          day_of_week?: number
          employee_id?: string
          end_time?: string
          id?: string
          start_time?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_availability_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_availability_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_availability_exceptions: {
        Row: {
          created_at: string
          employee_id: string
          end_time: string | null
          exception_date: string
          id: string
          is_available: boolean
          leave_request_id: string | null
          reason: string | null
          start_time: string | null
          tenant_id: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          end_time?: string | null
          exception_date: string
          id?: string
          is_available: boolean
          leave_request_id?: string | null
          reason?: string | null
          start_time?: string | null
          tenant_id: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          end_time?: string | null
          exception_date?: string
          id?: string
          is_available?: boolean
          leave_request_id?: string | null
          reason?: string | null
          start_time?: string | null
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_availability_exceptions_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_availability_exceptions_leave_request_id_fkey"
            columns: ["leave_request_id"]
            isOneToOne: false
            referencedRelation: "leave_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_availability_exceptions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employees: {
        Row: {
          created_at: string
          department_id: string | null
          email: string | null
          employee_number: string
          employment_end_date: string | null
          employment_start_date: string
          employment_status: Database["public"]["Enums"]["employment_status"]
          employment_type: Database["public"]["Enums"]["employment_type"]
          first_name: string
          home_site_id: string | null
          id: string
          last_name: string
          phone: string | null
          position_id: string | null
          profile_id: string | null
          region_id: string | null
          supervisor_id: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          department_id?: string | null
          email?: string | null
          employee_number: string
          employment_end_date?: string | null
          employment_start_date?: string
          employment_status?: Database["public"]["Enums"]["employment_status"]
          employment_type?: Database["public"]["Enums"]["employment_type"]
          first_name: string
          home_site_id?: string | null
          id?: string
          last_name: string
          phone?: string | null
          position_id?: string | null
          profile_id?: string | null
          region_id?: string | null
          supervisor_id?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          department_id?: string | null
          email?: string | null
          employee_number?: string
          employment_end_date?: string | null
          employment_start_date?: string
          employment_status?: Database["public"]["Enums"]["employment_status"]
          employment_type?: Database["public"]["Enums"]["employment_type"]
          first_name?: string
          home_site_id?: string | null
          id?: string
          last_name?: string
          phone?: string | null
          position_id?: string | null
          profile_id?: string | null
          region_id?: string | null
          supervisor_id?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employees_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_home_site_id_fkey"
            columns: ["home_site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_position_id_fkey"
            columns: ["position_id"]
            isOneToOne: false
            referencedRelation: "positions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "regions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leave_requests: {
        Row: {
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_notes: string | null
          employee_id: string
          end_date: string
          half_day_period: string | null
          id: string
          is_half_day: boolean
          leave_type_id: string
          reason: string | null
          start_date: string
          status: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_notes?: string | null
          employee_id: string
          end_date: string
          half_day_period?: string | null
          id?: string
          is_half_day?: boolean
          leave_type_id: string
          reason?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_notes?: string | null
          employee_id?: string
          end_date?: string
          half_day_period?: string | null
          id?: string
          is_half_day?: boolean
          leave_type_id?: string
          reason?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_requests_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_decided_by_fkey"
            columns: ["decided_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_leave_type_id_fkey"
            columns: ["leave_type_id"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leave_types: {
        Row: {
          created_at: string
          default_annual_days: number | null
          id: string
          is_paid: boolean
          name: string
          requires_documentation: boolean
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          default_annual_days?: number | null
          id?: string
          is_paid?: boolean
          name: string
          requires_documentation?: boolean
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          default_annual_days?: number | null
          id?: string
          is_paid?: boolean
          name?: string
          requires_documentation?: boolean
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_types_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leave_policies: {
        Row: {
          created_at: string
          default_annual_days: number | null
          id: string
          leave_type_id: string
          max_carry_over_days: number | null
          max_consecutive_days: number | null
          min_notice_days: number
          requires_documentation: boolean
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          default_annual_days?: number | null
          id?: string
          leave_type_id: string
          max_carry_over_days?: number | null
          max_consecutive_days?: number | null
          min_notice_days?: number
          requires_documentation?: boolean
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          default_annual_days?: number | null
          id?: string
          leave_type_id?: string
          max_carry_over_days?: number | null
          max_consecutive_days?: number | null
          min_notice_days?: number
          requires_documentation?: boolean
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_policies_leave_type_id_fkey"
            columns: ["leave_type_id"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_policies_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leave_balances: {
        Row: {
          accrued: number
          adjustment: number
          carried_over: number
          created_at: string
          employee_id: string
          id: string
          leave_type_id: string
          opening_balance: number
          pending: number
          period_year: number
          remaining: number
          tenant_id: string
          updated_at: string
          used: number
        }
        Insert: {
          accrued?: number
          adjustment?: number
          carried_over?: number
          created_at?: string
          employee_id: string
          id?: string
          leave_type_id: string
          opening_balance?: number
          pending?: number
          period_year: number
          remaining?: number
          tenant_id: string
          updated_at?: string
          used?: number
        }
        Update: {
          accrued?: number
          adjustment?: number
          carried_over?: number
          created_at?: string
          employee_id?: string
          id?: string
          leave_type_id?: string
          opening_balance?: number
          pending?: number
          period_year?: number
          remaining?: number
          tenant_id?: string
          updated_at?: string
          used?: number
        }
        Relationships: [
          {
            foreignKeyName: "leave_balances_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_balances_leave_type_id_fkey"
            columns: ["leave_type_id"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_balances_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leave_balance_transactions: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          employee_id: string
          id: string
          leave_request_id: string | null
          leave_type_id: string
          period_year: number
          tenant_id: string
          transaction_type: string
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          employee_id: string
          id?: string
          leave_request_id?: string | null
          leave_type_id: string
          period_year: number
          tenant_id: string
          transaction_type: string
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          employee_id?: string
          id?: string
          leave_request_id?: string | null
          leave_type_id?: string
          period_year?: number
          tenant_id?: string
          transaction_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_balance_transactions_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_balance_transactions_leave_request_id_fkey"
            columns: ["leave_request_id"]
            isOneToOne: false
            referencedRelation: "leave_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_balance_transactions_leave_type_id_fkey"
            columns: ["leave_type_id"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_balance_transactions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          email_enabled: boolean
          profile_id: string
          quiet_hours_end: string | null
          quiet_hours_start: string | null
          sms_enabled: boolean
          updated_at: string
          whatsapp_enabled: boolean
        }
        Insert: {
          email_enabled?: boolean
          profile_id: string
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          sms_enabled?: boolean
          updated_at?: string
          whatsapp_enabled?: boolean
        }
        Update: {
          email_enabled?: boolean
          profile_id?: string
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          sms_enabled?: boolean
          updated_at?: string
          whatsapp_enabled?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string
          created_at: string
          email_status: Database["public"]["Enums"]["notification_email_status"]
          id: string
          link_path: string | null
          read_at: string | null
          recipient_profile_id: string
          related_entity_id: string | null
          related_entity_table: string | null
          tenant_id: string | null
          title: string
          type: string
        }
        Insert: {
          body: string
          created_at?: string
          email_status?: Database["public"]["Enums"]["notification_email_status"]
          id?: string
          link_path?: string | null
          read_at?: string | null
          recipient_profile_id: string
          related_entity_id?: string | null
          related_entity_table?: string | null
          tenant_id?: string | null
          title: string
          type: string
        }
        Update: {
          body?: string
          created_at?: string
          email_status?: Database["public"]["Enums"]["notification_email_status"]
          id?: string
          link_path?: string | null
          read_at?: string | null
          recipient_profile_id?: string
          related_entity_id?: string | null
          related_entity_table?: string | null
          tenant_id?: string | null
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_recipient_profile_id_fkey"
            columns: ["recipient_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          address: string | null
          created_at: string
          currency: string
          email: string | null
          id: string
          industry: string | null
          language: string
          logo_url: string | null
          name: string
          phone: string | null
          registration_number: string | null
          status: Database["public"]["Enums"]["organization_status"]
          timezone: string
          updated_at: string
          website: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string
          currency?: string
          email?: string | null
          id?: string
          industry?: string | null
          language?: string
          logo_url?: string | null
          name: string
          phone?: string | null
          registration_number?: string | null
          status?: Database["public"]["Enums"]["organization_status"]
          timezone?: string
          updated_at?: string
          website?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string
          currency?: string
          email?: string | null
          id?: string
          industry?: string | null
          language?: string
          logo_url?: string | null
          name?: string
          phone?: string | null
          registration_number?: string | null
          status?: Database["public"]["Enums"]["organization_status"]
          timezone?: string
          updated_at?: string
          website?: string | null
        }
        Relationships: []
      }
      positions: {
        Row: {
          created_at: string
          department_id: string | null
          id: string
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          department_id?: string | null
          id?: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          department_id?: string | null
          id?: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "positions_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "positions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string
          first_name: string
          id: string
          last_name: string
          phone: string | null
          role: Database["public"]["Enums"]["user_role"] | null
          status: Database["public"]["Enums"]["profile_status"]
          tenant_id: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email: string
          first_name: string
          id: string
          last_name: string
          phone?: string | null
          role?: Database["public"]["Enums"]["user_role"] | null
          status?: Database["public"]["Enums"]["profile_status"]
          tenant_id?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string
          first_name?: string
          id?: string
          last_name?: string
          phone?: string | null
          role?: Database["public"]["Enums"]["user_role"] | null
          status?: Database["public"]["Enums"]["profile_status"]
          tenant_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      regions: {
        Row: {
          code: string | null
          created_at: string
          id: string
          name: string
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          code?: string | null
          created_at?: string
          id?: string
          name: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          code?: string | null
          created_at?: string
          id?: string
          name?: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "regions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_definitions: {
        Row: {
          break_minutes: number
          created_at: string
          end_time: string
          id: string
          is_overnight: boolean
          name: string
          start_time: string
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          break_minutes?: number
          created_at?: string
          end_time: string
          id?: string
          is_overnight?: boolean
          name: string
          start_time: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          break_minutes?: number
          created_at?: string
          end_time?: string
          id?: string
          is_overnight?: boolean
          name?: string
          start_time?: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_definitions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_substitutions: {
        Row: {
          created_at: string
          id: string
          original_employee_id: string
          reason: string | null
          shift_id: string
          substitute_employee_id: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          original_employee_id: string
          reason?: string | null
          shift_id: string
          substitute_employee_id: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          id?: string
          original_employee_id?: string
          reason?: string | null
          shift_id?: string
          substitute_employee_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_substitutions_original_employee_id_fkey"
            columns: ["original_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_substitutions_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shifts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_substitutions_substitute_employee_id_fkey"
            columns: ["substitute_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_substitutions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      shifts: {
        Row: {
          created_at: string
          employee_id: string
          ends_at: string
          id: string
          notes: string | null
          shift_definition_id: string | null
          site_id: string
          starts_at: string
          status: Database["public"]["Enums"]["shift_status"]
          supervisor_id: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          ends_at: string
          id?: string
          notes?: string | null
          shift_definition_id?: string | null
          site_id: string
          starts_at: string
          status?: Database["public"]["Enums"]["shift_status"]
          supervisor_id?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          ends_at?: string
          id?: string
          notes?: string | null
          shift_definition_id?: string | null
          site_id?: string
          starts_at?: string
          status?: Database["public"]["Enums"]["shift_status"]
          supervisor_id?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "shifts_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_shift_definition_id_fkey"
            columns: ["shift_definition_id"]
            isOneToOne: false
            referencedRelation: "shift_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      site_assignments: {
        Row: {
          created_at: string
          employee_id: string
          end_date: string | null
          id: string
          role_on_site: string | null
          site_id: string
          start_date: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          end_date?: string | null
          id?: string
          role_on_site?: string | null
          site_id: string
          start_date?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          end_date?: string | null
          id?: string
          role_on_site?: string | null
          site_id?: string
          start_date?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "site_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_assignments_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_assignments_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      site_staffing_requirements: {
        Row: {
          created_at: string
          id: string
          label: string
          required_count: number
          site_id: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          label: string
          required_count: number
          site_id: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          label?: string
          required_count?: number
          site_id?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "site_staffing_requirements_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_staffing_requirements_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      sites: {
        Row: {
          address: string | null
          client_id: string
          created_at: string
          id: string
          name: string
          region_id: string | null
          site_type: string | null
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          address?: string | null
          client_id: string
          created_at?: string
          id?: string
          name: string
          region_id?: string | null
          site_type?: string | null
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          address?: string | null
          client_id?: string
          created_at?: string
          id?: string
          name?: string
          region_id?: string | null
          site_type?: string | null
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sites_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sites_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "regions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sites_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      task_comments: {
        Row: {
          author_id: string | null
          body: string
          created_at: string
          id: string
          task_id: string
          tenant_id: string
        }
        Insert: {
          author_id?: string | null
          body: string
          created_at?: string
          id?: string
          task_id: string
          tenant_id: string
        }
        Update: {
          author_id?: string | null
          body?: string
          created_at?: string
          id?: string
          task_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_comments_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_comments_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks: {
        Row: {
          assignee_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_at: string | null
          id: string
          priority: Database["public"]["Enums"]["task_priority"]
          requires_evidence: boolean
          site_id: string
          status: Database["public"]["Enums"]["task_status"]
          supervisor_id: string | null
          team_id: string | null
          tenant_id: string
          title: string
          updated_at: string
        }
        Insert: {
          assignee_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_at?: string | null
          id?: string
          priority?: Database["public"]["Enums"]["task_priority"]
          requires_evidence?: boolean
          site_id: string
          status?: Database["public"]["Enums"]["task_status"]
          supervisor_id?: string | null
          team_id?: string | null
          tenant_id: string
          title: string
          updated_at?: string
        }
        Update: {
          assignee_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          due_at?: string | null
          id?: string
          priority?: Database["public"]["Enums"]["task_priority"]
          requires_evidence?: boolean
          site_id?: string
          status?: Database["public"]["Enums"]["task_status"]
          supervisor_id?: string | null
          team_id?: string | null
          tenant_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tasks_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      task_checklist_items: {
        Row: {
          completed_at: string | null
          completed_by: string | null
          created_at: string
          id: string
          is_completed: boolean
          label: string
          notes: string | null
          sort_order: number
          task_id: string
          tenant_id: string
        }
        Insert: {
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          id?: string
          is_completed?: boolean
          label: string
          notes?: string | null
          sort_order?: number
          task_id: string
          tenant_id: string
        }
        Update: {
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          id?: string
          is_completed?: boolean
          label?: string
          notes?: string | null
          sort_order?: number
          task_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_checklist_items_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_checklist_items_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      task_evidence: {
        Row: {
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["task_evidence_kind"]
          note: string | null
          submitted_by: string | null
          task_id: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["task_evidence_kind"]
          note?: string | null
          submitted_by?: string | null
          task_id: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["task_evidence_kind"]
          note?: string | null
          submitted_by?: string | null
          task_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_evidence_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_evidence_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      task_templates: {
        Row: {
          created_at: string
          default_assignee_id: string | null
          default_team_id: string | null
          description: string | null
          expected_duration_minutes: number | null
          id: string
          instructions: string | null
          last_generated_on: string | null
          priority: Database["public"]["Enums"]["task_priority"]
          recurrence_frequency: string | null
          requires_evidence: boolean
          site_id: string
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          default_assignee_id?: string | null
          default_team_id?: string | null
          description?: string | null
          expected_duration_minutes?: number | null
          id?: string
          instructions?: string | null
          last_generated_on?: string | null
          priority?: Database["public"]["Enums"]["task_priority"]
          recurrence_frequency?: string | null
          requires_evidence?: boolean
          site_id: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          default_assignee_id?: string | null
          default_team_id?: string | null
          description?: string | null
          expected_duration_minutes?: number | null
          id?: string
          instructions?: string | null
          last_generated_on?: string | null
          priority?: Database["public"]["Enums"]["task_priority"]
          recurrence_frequency?: string | null
          requires_evidence?: boolean
          site_id?: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_templates_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_templates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      team_members: {
        Row: {
          employee_id: string
          joined_at: string
          team_id: string
          tenant_id: string
        }
        Insert: {
          employee_id: string
          joined_at?: string
          team_id: string
          tenant_id: string
        }
        Update: {
          employee_id?: string
          joined_at?: string
          team_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "team_members_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "team_members_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "team_members_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      teams: {
        Row: {
          created_at: string
          id: string
          lead_employee_id: string | null
          name: string
          site_id: string | null
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          lead_employee_id?: string | null
          name: string
          site_id?: string | null
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          lead_employee_id?: string | null
          name?: string
          site_id?: string | null
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "teams_lead_employee_id_fkey"
            columns: ["lead_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teams_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teams_tenant_id_fkey"
            columns: ["tenant_id"]
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
      admin_create_user: {
        Args: {
          p_email: string
          p_first_name: string
          p_last_name: string
          p_phone: string
          p_role: Database["public"]["Enums"]["user_role"]
          p_tenant_id?: string
        }
        Returns: {
          temporary_password: string
          user_id: string
        }[]
      }
      admin_update_user_role: {
        Args: {
          p_new_role: Database["public"]["Enums"]["user_role"]
          p_user_id: string
        }
        Returns: undefined
      }
      can_assign_role: {
        Args: {
          p_new_role: Database["public"]["Enums"]["user_role"]
          p_target_current_role: Database["public"]["Enums"]["user_role"]
        }
        Returns: boolean
      }
      can_manage_employees: {
        Args: { target_tenant_id: string }
        Returns: boolean
      }
      can_manage_operations: {
        Args: { target_tenant_id: string }
        Returns: boolean
      }
      can_manage_org_structure: {
        Args: { target_tenant_id: string }
        Returns: boolean
      }
      can_manage_profiles: {
        Args: { target_tenant_id: string }
        Returns: boolean
      }
      compute_attendance_metrics: {
        Args: { p_attendance_record_id: string }
        Returns: {
          clock_in_at: string | null
          clock_out_at: string | null
          created_at: string
          early_departure_minutes: number | null
          employee_id: string
          id: string
          late_minutes: number | null
          notes: string | null
          overtime_minutes: number | null
          recorded_by: string | null
          shift_id: string | null
          site_id: string
          status: Database["public"]["Enums"]["attendance_status"]
          tenant_id: string
          updated_at: string
          worked_minutes: number | null
        }
        SetofOptions: {
          from: "*"
          to: "attendance_records"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clock_in: {
        Args: { p_employee_id: string; p_shift_id?: string; p_site_id: string }
        Returns: {
          clock_in_at: string | null
          clock_out_at: string | null
          created_at: string
          early_departure_minutes: number | null
          employee_id: string
          id: string
          late_minutes: number | null
          notes: string | null
          overtime_minutes: number | null
          recorded_by: string | null
          shift_id: string | null
          site_id: string
          status: Database["public"]["Enums"]["attendance_status"]
          tenant_id: string
          updated_at: string
          worked_minutes: number | null
        }
        SetofOptions: {
          from: "*"
          to: "attendance_records"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clock_out: {
        Args: { p_attendance_record_id: string }
        Returns: {
          clock_in_at: string | null
          clock_out_at: string | null
          created_at: string
          early_departure_minutes: number | null
          employee_id: string
          id: string
          late_minutes: number | null
          notes: string | null
          overtime_minutes: number | null
          recorded_by: string | null
          shift_id: string | null
          site_id: string
          status: Database["public"]["Enums"]["attendance_status"]
          tenant_id: string
          updated_at: string
          worked_minutes: number | null
        }
        SetofOptions: {
          from: "*"
          to: "attendance_records"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start_break: {
        Args: { p_attendance_record_id: string }
        Returns: {
          attendance_record_id: string
          break_end: string | null
          break_start: string
          created_at: string
          id: string
          tenant_id: string
        }
        SetofOptions: {
          from: "*"
          to: "attendance_breaks"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      end_break: {
        Args: { p_attendance_record_id: string }
        Returns: {
          attendance_record_id: string
          break_end: string | null
          break_start: string
          created_at: string
          id: string
          tenant_id: string
        }
        SetofOptions: {
          from: "*"
          to: "attendance_breaks"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      request_attendance_correction: {
        Args: {
          p_attendance_record_id: string
          p_field: Database["public"]["Enums"]["attendance_correction_field"]
          p_new_value: string
          p_reason: string
        }
        Returns: {
          attendance_record_id: string
          created_at: string
          field: Database["public"]["Enums"]["attendance_correction_field"]
          id: string
          new_value: string
          previous_value: string | null
          reason: string
          requested_by: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["attendance_correction_status"]
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "attendance_corrections"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      decide_attendance_correction: {
        Args: {
          p_approve: boolean
          p_correction_id: string
          p_review_notes?: string
        }
        Returns: {
          attendance_record_id: string
          created_at: string
          field: Database["public"]["Enums"]["attendance_correction_field"]
          id: string
          new_value: string
          previous_value: string | null
          reason: string
          requested_by: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["attendance_correction_status"]
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "attendance_corrections"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      complete_task: {
        Args: { p_task_id: string }
        Returns: {
          assignee_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_at: string | null
          id: string
          priority: Database["public"]["Enums"]["task_priority"]
          requires_evidence: boolean
          site_id: string
          status: Database["public"]["Enums"]["task_status"]
          supervisor_id: string | null
          team_id: string | null
          tenant_id: string
          title: string
          updated_at: string
        }
        SetofOptions: { from: "*"; to: "tasks"; isOneToOne: true; isSetofReturn: false }
      }
      verify_task: {
        Args: { p_task_id: string }
        Returns: {
          assignee_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_at: string | null
          id: string
          priority: Database["public"]["Enums"]["task_priority"]
          requires_evidence: boolean
          site_id: string
          status: Database["public"]["Enums"]["task_status"]
          supervisor_id: string | null
          team_id: string | null
          tenant_id: string
          title: string
          updated_at: string
        }
        SetofOptions: { from: "*"; to: "tasks"; isOneToOne: true; isSetofReturn: false }
      }
      reassign_task: {
        Args: { p_new_assignee_id: string; p_reason?: string; p_task_id: string }
        Returns: {
          assignee_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_at: string | null
          id: string
          priority: Database["public"]["Enums"]["task_priority"]
          requires_evidence: boolean
          site_id: string
          status: Database["public"]["Enums"]["task_status"]
          supervisor_id: string | null
          team_id: string | null
          tenant_id: string
          title: string
          updated_at: string
        }
        SetofOptions: { from: "*"; to: "tasks"; isOneToOne: true; isSetofReturn: false }
      }
      generate_recurring_tasks: {
        Args: { p_tenant_id: string }
        Returns: {
          assignee_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_at: string | null
          id: string
          priority: Database["public"]["Enums"]["task_priority"]
          requires_evidence: boolean
          site_id: string
          status: Database["public"]["Enums"]["task_status"]
          supervisor_id: string | null
          team_id: string | null
          tenant_id: string
          title: string
          updated_at: string
        }[]
        SetofOptions: { from: "*"; to: "tasks"; isOneToOne: false; isSetofReturn: true }
      }
      escalate_overdue_tasks: {
        Args: { p_tenant_id: string }
        Returns: {
          assignee_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          description: string | null
          due_at: string | null
          id: string
          priority: Database["public"]["Enums"]["task_priority"]
          requires_evidence: boolean
          site_id: string
          status: Database["public"]["Enums"]["task_status"]
          supervisor_id: string | null
          team_id: string | null
          tenant_id: string
          title: string
          updated_at: string
        }[]
        SetofOptions: { from: "*"; to: "tasks"; isOneToOne: false; isSetofReturn: true }
      }
      can_approve_leave: {
        Args: { target_tenant_id: string }
        Returns: boolean
      }
      can_manage_leave: {
        Args: { target_tenant_id: string }
        Returns: boolean
      }
      can_view_leave_broad: {
        Args: { target_tenant_id: string }
        Returns: boolean
      }
      leave_request_duration_days: {
        Args: {
          p_end_date: string
          p_is_half_day: boolean
          p_start_date: string
        }
        Returns: number
      }
      submit_leave_request: {
        Args: {
          p_employee_id: string
          p_end_date: string
          p_half_day_period?: string
          p_is_half_day?: boolean
          p_leave_type_id: string
          p_reason?: string
          p_start_date: string
          p_supporting_document_ref?: string
        }
        Returns: {
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_notes: string | null
          employee_id: string
          end_date: string
          half_day_period: string | null
          id: string
          is_half_day: boolean
          leave_type_id: string
          reason: string | null
          start_date: string
          status: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref: string | null
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "leave_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cancel_leave_request: {
        Args: { p_leave_request_id: string }
        Returns: {
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_notes: string | null
          employee_id: string
          end_date: string
          half_day_period: string | null
          id: string
          is_half_day: boolean
          leave_type_id: string
          reason: string | null
          start_date: string
          status: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref: string | null
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "leave_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_leave_request: {
        Args: { p_decision_notes?: string; p_leave_request_id: string }
        Returns: {
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_notes: string | null
          employee_id: string
          end_date: string
          half_day_period: string | null
          id: string
          is_half_day: boolean
          leave_type_id: string
          reason: string | null
          start_date: string
          status: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref: string | null
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "leave_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_leave_request: {
        Args: { p_decision_notes?: string; p_leave_request_id: string }
        Returns: {
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_notes: string | null
          employee_id: string
          end_date: string
          half_day_period: string | null
          id: string
          is_half_day: boolean
          leave_type_id: string
          reason: string | null
          start_date: string
          status: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref: string | null
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "leave_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      revoke_leave_request: {
        Args: { p_decision_notes?: string; p_leave_request_id: string }
        Returns: {
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_notes: string | null
          employee_id: string
          end_date: string
          half_day_period: string | null
          id: string
          is_half_day: boolean
          leave_type_id: string
          reason: string | null
          start_date: string
          status: Database["public"]["Enums"]["leave_status"]
          supporting_document_ref: string | null
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "leave_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      adjust_leave_balance: {
        Args: {
          p_amount: number
          p_employee_id: string
          p_leave_type_id: string
          p_note?: string
          p_period_year: number
        }
        Returns: {
          accrued: number
          adjustment: number
          carried_over: number
          created_at: string
          employee_id: string
          id: string
          leave_type_id: string
          opening_balance: number
          pending: number
          period_year: number
          remaining: number
          tenant_id: string
          updated_at: string
          used: number
        }
        SetofOptions: {
          from: "*"
          to: "leave_balances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      recompute_leave_balance: {
        Args: {
          p_employee_id: string
          p_leave_type_id: string
          p_period_year: number
        }
        Returns: {
          accrued: number
          adjustment: number
          carried_over: number
          created_at: string
          employee_id: string
          id: string
          leave_type_id: string
          opening_balance: number
          pending: number
          period_year: number
          remaining: number
          tenant_id: string
          updated_at: string
          used: number
        }
        SetofOptions: {
          from: "*"
          to: "leave_balances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_leave_affected_shifts: {
        Args: { p_leave_request_id: string }
        Returns: {
          created_at: string
          employee_id: string
          ends_at: string
          id: string
          notes: string | null
          shift_definition_id: string | null
          site_id: string
          starts_at: string
          status: Database["public"]["Enums"]["shift_status"]
          supervisor_id: string | null
          tenant_id: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "shifts"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      create_notification: {
        Args: {
          p_body: string
          p_link_path?: string
          p_recipient_profile_id: string
          p_related_entity_id?: string
          p_related_entity_table?: string
          p_tenant_id?: string
          p_title: string
          p_type: string
        }
        Returns: {
          body: string
          created_at: string
          email_status: Database["public"]["Enums"]["notification_email_status"]
          id: string
          link_path: string | null
          read_at: string | null
          recipient_profile_id: string
          related_entity_id: string | null
          related_entity_table: string | null
          tenant_id: string | null
          title: string
          type: string
        }
        SetofOptions: {
          from: "*"
          to: "notifications"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      current_tenant_id: { Args: never; Returns: string }
      is_platform_admin: { Args: never; Returns: boolean }
      provision_employee_login: {
        Args: {
          p_employee_id: string
          p_phone?: string
          p_role: Database["public"]["Enums"]["user_role"]
        }
        Returns: {
          temporary_password: string
          user_id: string
        }[]
      }
      reactivate_employee: {
        Args: { p_employee_id: string }
        Returns: {
          created_at: string
          department_id: string | null
          email: string | null
          employee_number: string
          employment_end_date: string | null
          employment_start_date: string
          employment_status: Database["public"]["Enums"]["employment_status"]
          employment_type: Database["public"]["Enums"]["employment_type"]
          first_name: string
          home_site_id: string | null
          id: string
          last_name: string
          phone: string | null
          position_id: string | null
          profile_id: string | null
          region_id: string | null
          supervisor_id: string | null
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employees"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      terminate_employee: {
        Args: { p_employee_id: string; p_termination_date: string }
        Returns: {
          created_at: string
          department_id: string | null
          email: string | null
          employee_number: string
          employment_end_date: string | null
          employment_start_date: string
          employment_status: Database["public"]["Enums"]["employment_status"]
          employment_type: Database["public"]["Enums"]["employment_type"]
          first_name: string
          home_site_id: string | null
          id: string
          last_name: string
          phone: string | null
          position_id: string | null
          profile_id: string | null
          region_id: string | null
          supervisor_id: string | null
          tenant_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employees"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      write_audit_log: {
        Args: {
          p_action: string
          p_actor_profile_id: string
          p_after?: Json
          p_before?: Json
          p_entity_id: string
          p_entity_table: string
          p_tenant_id: string
        }
        Returns: undefined
      }
    }
    Enums: {
      attendance_status:
        | "present"
        | "late"
        | "absent"
        | "excused"
        | "unconfirmed"
      attendance_correction_field: "clock_in_at" | "clock_out_at" | "status"
      attendance_correction_status: "pending" | "approved" | "rejected"
      contract_status: "draft" | "active" | "expired" | "terminated"
      employment_status: "active" | "on_leave" | "suspended" | "terminated"
      employment_type: "full_time" | "part_time" | "contract" | "temporary"
      entity_status: "active" | "inactive" | "onboarding" | "offboarded"
      leave_status: "pending" | "approved" | "rejected" | "cancelled" | "revoked"
      notification_email_status: "not_sent" | "sent" | "failed"
      organization_status: "pending" | "active" | "inactive" | "suspended"
      profile_status: "active" | "inactive" | "suspended"
      shift_status: "scheduled" | "confirmed" | "cancelled" | "completed"
      task_evidence_kind: "note" | "confirmation"
      task_priority: "low" | "normal" | "high" | "urgent"
      task_status:
        | "open"
        | "in_progress"
        | "completed"
        | "cancelled"
        | "escalated"
        | "verified"
      user_role:
        | "platform_administrator"
        | "organization_administrator"
        | "operations_manager"
        | "regional_manager"
        | "site_manager"
        | "supervisor"
        | "hr_user"
        | "employee"
        | "client_user"
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
    Enums: {
      attendance_status: [
        "present",
        "late",
        "absent",
        "excused",
        "unconfirmed",
      ],
      attendance_correction_field: ["clock_in_at", "clock_out_at", "status"],
      attendance_correction_status: ["pending", "approved", "rejected"],
      contract_status: ["draft", "active", "expired", "terminated"],
      employment_status: ["active", "on_leave", "suspended", "terminated"],
      employment_type: ["full_time", "part_time", "contract", "temporary"],
      entity_status: ["active", "inactive", "onboarding", "offboarded"],
      leave_status: ["pending", "approved", "rejected", "cancelled", "revoked"],
      notification_email_status: ["not_sent", "sent", "failed"],
      organization_status: ["pending", "active", "inactive", "suspended"],
      profile_status: ["active", "inactive", "suspended"],
      shift_status: ["scheduled", "confirmed", "cancelled", "completed"],
      task_evidence_kind: ["note", "confirmation"],
      task_priority: ["low", "normal", "high", "urgent"],
      task_status: [
        "open",
        "in_progress",
        "completed",
        "cancelled",
        "escalated",
        "verified",
      ],
      user_role: [
        "platform_administrator",
        "organization_administrator",
        "operations_manager",
        "regional_manager",
        "site_manager",
        "supervisor",
        "hr_user",
        "employee",
        "client_user",
      ],
    },
  },
} as const

