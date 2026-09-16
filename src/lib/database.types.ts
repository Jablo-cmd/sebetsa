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
          gps_verification_status: Database["public"]["Enums"]["gps_verification_status"]
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
          gps_verification_status?: Database["public"]["Enums"]["gps_verification_status"]
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
          gps_verification_status?: Database["public"]["Enums"]["gps_verification_status"]
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
      client_contacts: {
        Row: {
          client_id: string
          created_at: string
          email: string | null
          id: string
          is_primary: boolean
          name: string
          notes: string | null
          phone: string | null
          role_title: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          email?: string | null
          id?: string
          is_primary?: boolean
          name: string
          notes?: string | null
          phone?: string | null
          role_title?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          email?: string | null
          id?: string
          is_primary?: boolean
          name?: string
          notes?: string | null
          phone?: string | null
          role_title?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_contacts_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      contract_documents: {
        Row: {
          contract_id: string
          created_at: string
          file_name: string
          file_size_bytes: number
          id: string
          mime_type: string
          storage_path: string
          tenant_id: string
          uploaded_by: string | null
          version: number
        }
        Insert: {
          contract_id: string
          created_at?: string
          file_name: string
          file_size_bytes: number
          id?: string
          mime_type: string
          storage_path: string
          tenant_id: string
          uploaded_by?: string | null
          version?: number
        }
        Update: {
          contract_id?: string
          created_at?: string
          file_name?: string
          file_size_bytes?: number
          id?: string
          mime_type?: string
          storage_path?: string
          tenant_id?: string
          uploaded_by?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "contract_documents_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "contracts"
            referencedColumns: ["id"]
          },
        ]
      }
      sla_definitions: {
        Row: {
          contract_id: string
          created_at: string
          id: string
          is_active: boolean
          measurement_period: string
          metric_type: Database["public"]["Enums"]["sla_metric_type"]
          name: string
          site_id: string | null
          target_value: number
          tenant_id: string
          threshold_operator: string
          updated_at: string
        }
        Insert: {
          contract_id: string
          created_at?: string
          id?: string
          is_active?: boolean
          measurement_period?: string
          metric_type: Database["public"]["Enums"]["sla_metric_type"]
          name: string
          site_id?: string | null
          target_value: number
          tenant_id: string
          threshold_operator: string
          updated_at?: string
        }
        Update: {
          contract_id?: string
          created_at?: string
          id?: string
          is_active?: boolean
          measurement_period?: string
          metric_type?: Database["public"]["Enums"]["sla_metric_type"]
          name?: string
          site_id?: string | null
          target_value?: number
          tenant_id?: string
          threshold_operator?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sla_definitions_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "contracts"
            referencedColumns: ["id"]
          },
        ]
      }
      sla_measurements: {
        Row: {
          computed_at: string
          computed_by: string | null
          id: string
          measured_value: number
          period_end: string
          period_start: string
          sla_definition_id: string
          target_met: boolean
          tenant_id: string
        }
        Insert: {
          computed_at?: string
          computed_by?: string | null
          id?: string
          measured_value: number
          period_end: string
          period_start: string
          sla_definition_id: string
          target_met: boolean
          tenant_id: string
        }
        Update: {
          computed_at?: string
          computed_by?: string | null
          id?: string
          measured_value?: number
          period_end?: string
          period_start?: string
          sla_definition_id?: string
          target_met?: boolean
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sla_measurements_sla_definition_id_fkey"
            columns: ["sla_definition_id"]
            isOneToOne: false
            referencedRelation: "sla_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      contracts: {
        Row: {
          auto_renew: boolean
          client_id: string
          consumables_responsibility: Database["public"]["Enums"]["contract_party_responsibility"] | null
          contract_number: string
          contract_value: number | null
          created_at: string
          equipment_responsibility: Database["public"]["Enums"]["contract_party_responsibility"] | null
          escalation_notes: string | null
          escalation_percentage: number | null
          billing_frequency: Database["public"]["Enums"]["contract_billing_frequency"] | null
          end_date: string | null
          id: string
          labour_notes: string | null
          notes: string | null
          payment_terms_days: number | null
          recurring_value: number | null
          renewal_date: string | null
          responsible_manager_id: string | null
          service_frequency: string | null
          sla_notes: string | null
          start_date: string
          status: Database["public"]["Enums"]["contract_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          auto_renew?: boolean
          client_id: string
          consumables_responsibility?: Database["public"]["Enums"]["contract_party_responsibility"] | null
          contract_number: string
          contract_value?: number | null
          created_at?: string
          equipment_responsibility?: Database["public"]["Enums"]["contract_party_responsibility"] | null
          escalation_notes?: string | null
          escalation_percentage?: number | null
          billing_frequency?: Database["public"]["Enums"]["contract_billing_frequency"] | null
          end_date?: string | null
          id?: string
          labour_notes?: string | null
          notes?: string | null
          payment_terms_days?: number | null
          recurring_value?: number | null
          renewal_date?: string | null
          responsible_manager_id?: string | null
          service_frequency?: string | null
          sla_notes?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["contract_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          auto_renew?: boolean
          client_id?: string
          consumables_responsibility?: Database["public"]["Enums"]["contract_party_responsibility"] | null
          contract_number?: string
          contract_value?: number | null
          created_at?: string
          equipment_responsibility?: Database["public"]["Enums"]["contract_party_responsibility"] | null
          escalation_notes?: string | null
          escalation_percentage?: number | null
          billing_frequency?: Database["public"]["Enums"]["contract_billing_frequency"] | null
          end_date?: string | null
          id?: string
          labour_notes?: string | null
          notes?: string | null
          payment_terms_days?: number | null
          recurring_value?: number | null
          renewal_date?: string | null
          responsible_manager_id?: string | null
          service_frequency?: string | null
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
      contract_versions: {
        Row: {
          change_summary: string
          changed_by: string | null
          contract_id: string
          created_at: string
          effective_date: string
          id: string
          snapshot: Json
          tenant_id: string
          version_number: number
        }
        Insert: {
          change_summary: string
          changed_by?: string | null
          contract_id: string
          created_at?: string
          effective_date?: string
          id?: string
          snapshot: Json
          tenant_id: string
          version_number: number
        }
        Update: {
          change_summary?: string
          changed_by?: string | null
          contract_id?: string
          created_at?: string
          effective_date?: string
          id?: string
          snapshot?: Json
          tenant_id?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "contract_versions_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "contracts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_versions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      quotes: {
        Row: {
          client_id: string
          converted_to_contract_id: string | null
          created_at: string
          discount_amount: number
          exclusions: string | null
          expiry_date: string | null
          id: string
          notes: string | null
          assumptions: string | null
          prepared_by: string | null
          quote_number: string
          site_id: string | null
          status: Database["public"]["Enums"]["quote_status"]
          subtotal: number
          tax_amount: number
          tax_rate: number
          tenant_id: string
          total_amount: number
          updated_at: string
          version: number
        }
        Insert: {
          client_id: string
          converted_to_contract_id?: string | null
          created_at?: string
          discount_amount?: number
          exclusions?: string | null
          expiry_date?: string | null
          id?: string
          notes?: string | null
          assumptions?: string | null
          prepared_by?: string | null
          quote_number: string
          site_id?: string | null
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal?: number
          tax_amount?: number
          tax_rate?: number
          tenant_id: string
          total_amount?: number
          updated_at?: string
          version?: number
        }
        Update: {
          client_id?: string
          converted_to_contract_id?: string | null
          created_at?: string
          discount_amount?: number
          exclusions?: string | null
          expiry_date?: string | null
          id?: string
          notes?: string | null
          assumptions?: string | null
          prepared_by?: string | null
          quote_number?: string
          site_id?: string | null
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal?: number
          tax_amount?: number
          tax_rate?: number
          tenant_id?: string
          total_amount?: number
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "quotes_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_converted_to_contract_id_fkey"
            columns: ["converted_to_contract_id"]
            isOneToOne: false
            referencedRelation: "contracts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_line_items: {
        Row: {
          category: Database["public"]["Enums"]["quote_line_category"]
          created_at: string
          description: string
          id: string
          line_total: number
          quantity: number
          quote_id: string
          sort_order: number
          tenant_id: string
          unit_rate: number
          updated_at: string
        }
        Insert: {
          category?: Database["public"]["Enums"]["quote_line_category"]
          created_at?: string
          description: string
          id?: string
          quantity: number
          quote_id: string
          sort_order?: number
          tenant_id: string
          unit_rate: number
          updated_at?: string
        }
        Update: {
          category?: Database["public"]["Enums"]["quote_line_category"]
          created_at?: string
          description?: string
          id?: string
          quantity?: number
          quote_id?: string
          sort_order?: number
          tenant_id?: string
          unit_rate?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_line_items_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_line_items_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      site_areas: {
        Row: {
          created_at: string
          description: string | null
          id: string
          name: string
          site_id: string
          sort_order: number
          status: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          name: string
          site_id: string
          sort_order?: number
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          site_id?: string
          sort_order?: number
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "site_areas_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_areas_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      scope_of_work_items: {
        Row: {
          assigned_role: string | null
          contract_id: string
          created_at: string
          estimated_minutes: number | null
          frequency: string | null
          id: string
          instructions: string | null
          ppe_notes: string | null
          priority: Database["public"]["Enums"]["task_priority"]
          required_consumables: string | null
          required_equipment: string | null
          requires_evidence: boolean
          site_area_id: string
          status: Database["public"]["Enums"]["entity_status"]
          task_name: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          assigned_role?: string | null
          contract_id: string
          created_at?: string
          estimated_minutes?: number | null
          frequency?: string | null
          id?: string
          instructions?: string | null
          ppe_notes?: string | null
          priority?: Database["public"]["Enums"]["task_priority"]
          required_consumables?: string | null
          required_equipment?: string | null
          requires_evidence?: boolean
          site_area_id: string
          status?: Database["public"]["Enums"]["entity_status"]
          task_name: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          assigned_role?: string | null
          contract_id?: string
          created_at?: string
          estimated_minutes?: number | null
          frequency?: string | null
          id?: string
          instructions?: string | null
          ppe_notes?: string | null
          priority?: Database["public"]["Enums"]["task_priority"]
          required_consumables?: string | null
          required_equipment?: string | null
          requires_evidence?: boolean
          site_area_id?: string
          status?: Database["public"]["Enums"]["entity_status"]
          task_name?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "scope_of_work_items_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "contracts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scope_of_work_items_site_area_id_fkey"
            columns: ["site_area_id"]
            isOneToOne: false
            referencedRelation: "site_areas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scope_of_work_items_tenant_id_fkey"
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
      employee_documents: {
        Row: {
          created_at: string
          employee_id: string
          expiry_date: string | null
          file_name: string
          file_size_bytes: number
          id: string
          mime_type: string
          review_notes: string | null
          status: Database["public"]["Enums"]["document_status"]
          storage_path: string
          supersedes_document_id: string | null
          tenant_id: string
          document_type: Database["public"]["Enums"]["document_type"]
          updated_at: string
          uploaded_by: string | null
          verified_at: string | null
          verified_by: string | null
          version: number
        }
        Insert: {
          created_at?: string
          employee_id: string
          expiry_date?: string | null
          file_name: string
          file_size_bytes: number
          id?: string
          mime_type: string
          review_notes?: string | null
          status?: Database["public"]["Enums"]["document_status"]
          storage_path: string
          supersedes_document_id?: string | null
          tenant_id: string
          document_type: Database["public"]["Enums"]["document_type"]
          updated_at?: string
          uploaded_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
          version?: number
        }
        Update: {
          created_at?: string
          employee_id?: string
          expiry_date?: string | null
          file_name?: string
          file_size_bytes?: number
          id?: string
          mime_type?: string
          review_notes?: string | null
          status?: Database["public"]["Enums"]["document_status"]
          storage_path?: string
          supersedes_document_id?: string | null
          tenant_id?: string
          document_type?: Database["public"]["Enums"]["document_type"]
          updated_at?: string
          uploaded_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "employee_documents_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_documents_supersedes_document_id_fkey"
            columns: ["supersedes_document_id"]
            isOneToOne: false
            referencedRelation: "employee_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_documents_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_requirements: {
        Row: {
          applies_to_scope: string
          category: string
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          is_active: boolean
          name: string
          recurrence_interval_days: number | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          applies_to_scope: string
          category: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          recurrence_interval_days?: number | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          applies_to_scope?: string
          category?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          recurrence_interval_days?: number | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "compliance_requirements_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_records: {
        Row: {
          client_id: string | null
          completed_date: string | null
          contract_id: string | null
          created_at: string
          due_date: string | null
          evidence_storage_path: string | null
          expiry_date: string | null
          id: string
          notes: string | null
          requirement_id: string
          responsible_profile_id: string | null
          site_id: string | null
          status: Database["public"]["Enums"]["compliance_status"]
          tenant_id: string
          updated_at: string
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          client_id?: string | null
          completed_date?: string | null
          contract_id?: string | null
          created_at?: string
          due_date?: string | null
          evidence_storage_path?: string | null
          expiry_date?: string | null
          id?: string
          notes?: string | null
          requirement_id: string
          responsible_profile_id?: string | null
          site_id?: string | null
          status?: Database["public"]["Enums"]["compliance_status"]
          tenant_id: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          client_id?: string | null
          completed_date?: string | null
          contract_id?: string | null
          created_at?: string
          due_date?: string | null
          evidence_storage_path?: string | null
          expiry_date?: string | null
          id?: string
          notes?: string | null
          requirement_id?: string
          responsible_profile_id?: string | null
          site_id?: string | null
          status?: Database["public"]["Enums"]["compliance_status"]
          tenant_id?: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_records_requirement_id_fkey"
            columns: ["requirement_id"]
            isOneToOne: false
            referencedRelation: "compliance_requirements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compliance_records_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      incidents: {
        Row: {
          category: Database["public"]["Enums"]["incident_category"]
          closed_at: string | null
          closed_by: string | null
          contract_id: string | null
          corrective_action_summary: string | null
          created_at: string
          description: string
          id: string
          investigation_notes: string | null
          occurred_at: string
          reference_number: string
          reported_by: string | null
          severity: Database["public"]["Enums"]["incident_severity"]
          site_id: string | null
          status: Database["public"]["Enums"]["incident_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          category: Database["public"]["Enums"]["incident_category"]
          closed_at?: string | null
          closed_by?: string | null
          contract_id?: string | null
          corrective_action_summary?: string | null
          created_at?: string
          description: string
          id?: string
          investigation_notes?: string | null
          occurred_at: string
          reference_number?: string
          reported_by?: string | null
          severity: Database["public"]["Enums"]["incident_severity"]
          site_id?: string | null
          status?: Database["public"]["Enums"]["incident_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          category?: Database["public"]["Enums"]["incident_category"]
          closed_at?: string | null
          closed_by?: string | null
          contract_id?: string | null
          corrective_action_summary?: string | null
          created_at?: string
          description?: string
          id?: string
          investigation_notes?: string | null
          occurred_at?: string
          reference_number?: string
          reported_by?: string | null
          severity?: Database["public"]["Enums"]["incident_severity"]
          site_id?: string | null
          status?: Database["public"]["Enums"]["incident_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "incidents_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      incident_affected_employees: {
        Row: {
          created_at: string
          employee_id: string
          id: string
          incident_id: string
          involvement: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          id?: string
          incident_id: string
          involvement?: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          id?: string
          incident_id?: string
          involvement?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "incident_affected_employees_incident_id_fkey"
            columns: ["incident_id"]
            isOneToOne: false
            referencedRelation: "incidents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "incident_affected_employees_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      incident_actions: {
        Row: {
          completed_at: string | null
          created_at: string
          description: string
          due_date: string | null
          id: string
          incident_id: string
          owner_profile_id: string | null
          status: Database["public"]["Enums"]["incident_action_status"]
          tenant_id: string
          updated_at: string
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          description: string
          due_date?: string | null
          id?: string
          incident_id: string
          owner_profile_id?: string | null
          status?: Database["public"]["Enums"]["incident_action_status"]
          tenant_id: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          description?: string
          due_date?: string | null
          id?: string
          incident_id?: string
          owner_profile_id?: string | null
          status?: Database["public"]["Enums"]["incident_action_status"]
          tenant_id?: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "incident_actions_incident_id_fkey"
            columns: ["incident_id"]
            isOneToOne: false
            referencedRelation: "incidents"
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
          scope_of_work_item_id: string | null
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
          scope_of_work_item_id?: string | null
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
          scope_of_work_item_id?: string | null
          site_id?: string
          status?: Database["public"]["Enums"]["entity_status"]
          tenant_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_templates_scope_of_work_item_id_fkey"
            columns: ["scope_of_work_item_id"]
            isOneToOne: false
            referencedRelation: "scope_of_work_items"
            referencedColumns: ["id"]
          },
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
      assets: {
        Row: {
          acquisition_cost: number | null
          acquisition_date: string | null
          asset_number: string
          category: string
          condition: string | null
          created_at: string
          custodian_employee_id: string | null
          id: string
          name: string
          notes: string | null
          serial_number: string | null
          site_id: string | null
          status: Database["public"]["Enums"]["asset_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          acquisition_cost?: number | null
          acquisition_date?: string | null
          asset_number: string
          category: string
          condition?: string | null
          created_at?: string
          custodian_employee_id?: string | null
          id?: string
          name: string
          notes?: string | null
          serial_number?: string | null
          site_id?: string | null
          status?: Database["public"]["Enums"]["asset_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          acquisition_cost?: number | null
          acquisition_date?: string | null
          asset_number?: string
          category?: string
          condition?: string | null
          created_at?: string
          custodian_employee_id?: string | null
          id?: string
          name?: string
          notes?: string | null
          serial_number?: string | null
          site_id?: string | null
          status?: Database["public"]["Enums"]["asset_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "assets_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_assignments: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          assigned_to_employee_id: string | null
          assigned_to_site_id: string | null
          assigned_to_team_id: string | null
          asset_id: string
          condition_at_assignment: string | null
          condition_at_return: string | null
          created_at: string
          id: string
          reason: string | null
          returned_at: string | null
          tenant_id: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          assigned_to_employee_id?: string | null
          assigned_to_site_id?: string | null
          assigned_to_team_id?: string | null
          asset_id: string
          condition_at_assignment?: string | null
          condition_at_return?: string | null
          created_at?: string
          id?: string
          reason?: string | null
          returned_at?: string | null
          tenant_id: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          assigned_to_employee_id?: string | null
          assigned_to_site_id?: string | null
          assigned_to_team_id?: string | null
          asset_id?: string
          condition_at_assignment?: string | null
          condition_at_return?: string | null
          created_at?: string
          id?: string
          reason?: string | null
          returned_at?: string | null
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_assignments_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_maintenance_records: {
        Row: {
          asset_id: string
          cost: number | null
          created_at: string
          description: string
          id: string
          performed_at: string
          performed_by: string | null
          tenant_id: string
        }
        Insert: {
          asset_id: string
          cost?: number | null
          created_at?: string
          description: string
          id?: string
          performed_at?: string
          performed_by?: string | null
          tenant_id: string
        }
        Update: {
          asset_id?: string
          cost?: number | null
          created_at?: string
          description?: string
          id?: string
          performed_at?: string
          performed_by?: string | null
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_maintenance_records_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_items: {
        Row: {
          category: string
          created_at: string
          id: string
          is_active: boolean
          name: string
          reorder_threshold: number | null
          sku: string
          tenant_id: string
          unit: string
          updated_at: string
        }
        Insert: {
          category: string
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          reorder_threshold?: number | null
          sku: string
          tenant_id: string
          unit?: string
          updated_at?: string
        }
        Update: {
          category?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          reorder_threshold?: number | null
          sku?: string
          tenant_id?: string
          unit?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_items_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_movements: {
        Row: {
          created_at: string
          id: string
          item_id: string
          movement_type: Database["public"]["Enums"]["inventory_movement_type"]
          performed_by: string | null
          quantity: number
          reference: string | null
          site_id: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          item_id: string
          movement_type: Database["public"]["Enums"]["inventory_movement_type"]
          performed_by?: string | null
          quantity: number
          reference?: string | null
          site_id: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          id?: string
          item_id?: string
          movement_type?: Database["public"]["Enums"]["inventory_movement_type"]
          performed_by?: string | null
          quantity?: number
          reference?: string | null
          site_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_movements_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "inventory_items"
            referencedColumns: ["id"]
          },
        ]
      }
      procurement_requests: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          estimated_cost: number | null
          id: string
          item_description: string
          quantity: number
          rejected_reason: string | null
          requested_by: string | null
          site_id: string | null
          status: Database["public"]["Enums"]["procurement_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          estimated_cost?: number | null
          id?: string
          item_description: string
          quantity: number
          rejected_reason?: string | null
          requested_by?: string | null
          site_id?: string | null
          status?: Database["public"]["Enums"]["procurement_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          estimated_cost?: number | null
          id?: string
          item_description?: string
          quantity?: number
          rejected_reason?: string | null
          requested_by?: string | null
          site_id?: string | null
          status?: Database["public"]["Enums"]["procurement_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "procurement_requests_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      skills: {
        Row: { category: string; created_at: string; id: string; name: string; tenant_id: string; updated_at: string }
        Insert: { category: string; created_at?: string; id?: string; name: string; tenant_id: string; updated_at?: string }
        Update: { category?: string; created_at?: string; id?: string; name?: string; tenant_id?: string; updated_at?: string }
        Relationships: [
          { foreignKeyName: "skills_tenant_id_fkey"; columns: ["tenant_id"]; isOneToOne: false; referencedRelation: "organizations"; referencedColumns: ["id"] },
        ]
      }
      employee_skills: {
        Row: {
          created_at: string
          employee_id: string
          evidence_document_id: string | null
          id: string
          proficiency_level: Database["public"]["Enums"]["proficiency_level"]
          skill_id: string
          tenant_id: string
          updated_at: string
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          created_at?: string
          employee_id: string
          evidence_document_id?: string | null
          id?: string
          proficiency_level?: Database["public"]["Enums"]["proficiency_level"]
          skill_id: string
          tenant_id: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          created_at?: string
          employee_id?: string
          evidence_document_id?: string | null
          id?: string
          proficiency_level?: Database["public"]["Enums"]["proficiency_level"]
          skill_id?: string
          tenant_id?: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          { foreignKeyName: "employee_skills_employee_id_fkey"; columns: ["employee_id"]; isOneToOne: false; referencedRelation: "employees"; referencedColumns: ["id"] },
          { foreignKeyName: "employee_skills_skill_id_fkey"; columns: ["skill_id"]; isOneToOne: false; referencedRelation: "skills"; referencedColumns: ["id"] },
        ]
      }
      employee_qualifications: {
        Row: {
          created_at: string
          credential_type: Database["public"]["Enums"]["credential_type"]
          employee_id: string
          evidence_document_id: string | null
          expiry_date: string | null
          id: string
          issue_date: string | null
          issuing_organization: string | null
          name: string
          status: Database["public"]["Enums"]["credential_status"]
          tenant_id: string
          updated_at: string
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          created_at?: string
          credential_type: Database["public"]["Enums"]["credential_type"]
          employee_id: string
          evidence_document_id?: string | null
          expiry_date?: string | null
          id?: string
          issue_date?: string | null
          issuing_organization?: string | null
          name: string
          status?: Database["public"]["Enums"]["credential_status"]
          tenant_id: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          created_at?: string
          credential_type?: Database["public"]["Enums"]["credential_type"]
          employee_id?: string
          evidence_document_id?: string | null
          expiry_date?: string | null
          id?: string
          issue_date?: string | null
          issuing_organization?: string | null
          name?: string
          status?: Database["public"]["Enums"]["credential_status"]
          tenant_id?: string
          updated_at?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          { foreignKeyName: "employee_qualifications_employee_id_fkey"; columns: ["employee_id"]; isOneToOne: false; referencedRelation: "employees"; referencedColumns: ["id"] },
        ]
      }
      training_programs: {
        Row: { category: string; created_at: string; description: string | null; id: string; is_active: boolean; name: string; tenant_id: string; updated_at: string }
        Insert: { category: string; created_at?: string; description?: string | null; id?: string; is_active?: boolean; name: string; tenant_id: string; updated_at?: string }
        Update: { category?: string; created_at?: string; description?: string | null; id?: string; is_active?: boolean; name?: string; tenant_id?: string; updated_at?: string }
        Relationships: [
          { foreignKeyName: "training_programs_tenant_id_fkey"; columns: ["tenant_id"]; isOneToOne: false; referencedRelation: "organizations"; referencedColumns: ["id"] },
        ]
      }
      training_requirements: {
        Row: { created_at: string; id: string; is_active: boolean; required_for_role: Database["public"]["Enums"]["user_role"] | null; required_for_site_id: string | null; tenant_id: string; training_program_id: string }
        Insert: { created_at?: string; id?: string; is_active?: boolean; required_for_role?: Database["public"]["Enums"]["user_role"] | null; required_for_site_id?: string | null; tenant_id: string; training_program_id: string }
        Update: { created_at?: string; id?: string; is_active?: boolean; required_for_role?: Database["public"]["Enums"]["user_role"] | null; required_for_site_id?: string | null; tenant_id?: string; training_program_id?: string }
        Relationships: [
          { foreignKeyName: "training_requirements_program_id_fkey"; columns: ["training_program_id"]; isOneToOne: false; referencedRelation: "training_programs"; referencedColumns: ["id"] },
        ]
      }
      training_enrollments: {
        Row: {
          completed_at: string | null
          created_at: string
          employee_id: string
          enrolled_at: string
          id: string
          result: string | null
          resulting_qualification_id: string | null
          status: Database["public"]["Enums"]["training_enrollment_status"]
          tenant_id: string
          training_program_id: string
          updated_at: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          employee_id: string
          enrolled_at?: string
          id?: string
          result?: string | null
          resulting_qualification_id?: string | null
          status?: Database["public"]["Enums"]["training_enrollment_status"]
          tenant_id: string
          training_program_id: string
          updated_at?: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          employee_id?: string
          enrolled_at?: string
          id?: string
          result?: string | null
          resulting_qualification_id?: string | null
          status?: Database["public"]["Enums"]["training_enrollment_status"]
          tenant_id?: string
          training_program_id?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "training_enrollments_program_id_fkey"; columns: ["training_program_id"]; isOneToOne: false; referencedRelation: "training_programs"; referencedColumns: ["id"] },
          { foreignKeyName: "training_enrollments_employee_id_fkey"; columns: ["employee_id"]; isOneToOne: false; referencedRelation: "employees"; referencedColumns: ["id"] },
        ]
      }
      performance_reviews: {
        Row: {
          created_at: string
          employee_id: string
          employee_comments: string | null
          finalized_at: string | null
          id: string
          manager_comments: string | null
          overall_rating: number | null
          review_period_end: string
          review_period_start: string
          reviewer_profile_id: string | null
          status: Database["public"]["Enums"]["performance_review_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          employee_comments?: string | null
          finalized_at?: string | null
          id?: string
          manager_comments?: string | null
          overall_rating?: number | null
          review_period_end: string
          review_period_start: string
          reviewer_profile_id?: string | null
          status?: Database["public"]["Enums"]["performance_review_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          employee_comments?: string | null
          finalized_at?: string | null
          id?: string
          manager_comments?: string | null
          overall_rating?: number | null
          review_period_end?: string
          review_period_start?: string
          reviewer_profile_id?: string | null
          status?: Database["public"]["Enums"]["performance_review_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "performance_reviews_employee_id_fkey"; columns: ["employee_id"]; isOneToOne: false; referencedRelation: "employees"; referencedColumns: ["id"] },
        ]
      }
      development_actions: {
        Row: {
          completed_at: string | null
          created_at: string
          employee_id: string
          goal: string
          id: string
          owner_profile_id: string | null
          review_id: string | null
          status: string
          target_date: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          employee_id: string
          goal: string
          id?: string
          owner_profile_id?: string | null
          review_id?: string | null
          status?: string
          target_date?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          employee_id?: string
          goal?: string
          id?: string
          owner_profile_id?: string | null
          review_id?: string | null
          status?: string
          target_date?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          { foreignKeyName: "development_actions_employee_id_fkey"; columns: ["employee_id"]; isOneToOne: false; referencedRelation: "employees"; referencedColumns: ["id"] },
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
      attendance_location_exceptions: {
        Row: {
          attendance_record_id: string
          created_at: string
          employee_id: string
          id: string
          reason: string
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          attendance_record_id: string
          created_at?: string
          employee_id: string
          id?: string
          reason: string
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          attendance_record_id?: string
          created_at?: string
          employee_id?: string
          id?: string
          reason?: string
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      patrol_routes: {
        Row: {
          active: boolean
          allowed_start_window_minutes: number
          completion_threshold_pct: number
          created_at: string
          expected_duration_minutes: number | null
          id: string
          name: string
          site_id: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          allowed_start_window_minutes?: number
          completion_threshold_pct?: number
          created_at?: string
          expected_duration_minutes?: number | null
          id?: string
          name: string
          site_id: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          allowed_start_window_minutes?: number
          completion_threshold_pct?: number
          created_at?: string
          expected_duration_minutes?: number | null
          id?: string
          name?: string
          site_id?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      patrol_runs: {
        Row: {
          completed_at: string | null
          created_at: string
          employee_id: string
          expected_checkpoint_count: number
          id: string
          patrol_route_id: string
          scanned_checkpoint_count: number
          site_id: string
          started_at: string
          status: Database["public"]["Enums"]["patrol_run_status"]
          tenant_id: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          employee_id: string
          expected_checkpoint_count: number
          id?: string
          patrol_route_id: string
          scanned_checkpoint_count?: number
          site_id: string
          started_at?: string
          status?: Database["public"]["Enums"]["patrol_run_status"]
          tenant_id: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          employee_id?: string
          expected_checkpoint_count?: number
          id?: string
          patrol_route_id?: string
          scanned_checkpoint_count?: number
          site_id?: string
          started_at?: string
          status?: Database["public"]["Enums"]["patrol_run_status"]
          tenant_id?: string
        }
        Relationships: []
      }
      patrol_checkpoint_scans: {
        Row: {
          checkpoint_id: string | null
          employee_id: string
          id: string
          latitude: number | null
          longitude: number | null
          patrol_run_id: string
          risk_flags: Json
          scan_method: Database["public"]["Enums"]["checkpoint_scan_type"]
          scanned_at: string
          scanned_code: string | null
          sequence_number: number
          tenant_id: string
          verification_result: Database["public"]["Enums"]["checkpoint_scan_result"]
        }
        Insert: {
          checkpoint_id?: string | null
          employee_id: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          patrol_run_id: string
          risk_flags?: Json
          scan_method?: Database["public"]["Enums"]["checkpoint_scan_type"]
          scanned_at?: string
          scanned_code?: string | null
          sequence_number: number
          tenant_id: string
          verification_result: Database["public"]["Enums"]["checkpoint_scan_result"]
        }
        Update: {
          checkpoint_id?: string | null
          employee_id?: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          patrol_run_id?: string
          risk_flags?: Json
          scan_method?: Database["public"]["Enums"]["checkpoint_scan_type"]
          scanned_at?: string
          scanned_code?: string | null
          sequence_number?: number
          tenant_id?: string
          verification_result?: Database["public"]["Enums"]["checkpoint_scan_result"]
        }
        Relationships: []
      }
      operational_alerts: {
        Row: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          alert_type: Database["public"]["Enums"]["operational_alert_type"]
          contract_id: string | null
          created_at: string
          employee_id: string | null
          id: string
          message: string
          resolution_notes: string | null
          resolved_at: string | null
          resolved_by: string | null
          severity: Database["public"]["Enums"]["alert_severity"]
          site_id: string | null
          status: Database["public"]["Enums"]["alert_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          alert_type: Database["public"]["Enums"]["operational_alert_type"]
          contract_id?: string | null
          created_at?: string
          employee_id?: string | null
          id?: string
          message: string
          resolution_notes?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          severity: Database["public"]["Enums"]["alert_severity"]
          site_id?: string | null
          status?: Database["public"]["Enums"]["alert_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          alert_type?: Database["public"]["Enums"]["operational_alert_type"]
          contract_id?: string | null
          created_at?: string
          employee_id?: string | null
          id?: string
          message?: string
          resolution_notes?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          severity?: Database["public"]["Enums"]["alert_severity"]
          site_id?: string | null
          status?: Database["public"]["Enums"]["alert_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      emergency_events: {
        Row: {
          accuracy_meters: number | null
          device_context: Json
          emergency_type: Database["public"]["Enums"]["emergency_type"]
          employee_id: string
          id: string
          latitude: number | null
          longitude: number | null
          shift_id: string | null
          site_id: string | null
          tenant_id: string
          triggered_at: string
        }
        Insert: {
          accuracy_meters?: number | null
          device_context?: Json
          emergency_type?: Database["public"]["Enums"]["emergency_type"]
          employee_id: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          shift_id?: string | null
          site_id?: string | null
          tenant_id: string
          triggered_at?: string
        }
        Update: {
          accuracy_meters?: number | null
          device_context?: Json
          emergency_type?: Database["public"]["Enums"]["emergency_type"]
          employee_id?: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          shift_id?: string | null
          site_id?: string | null
          tenant_id?: string
          triggered_at?: string
        }
        Relationships: []
      }
      emergency_responses: {
        Row: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          created_at: string
          emergency_event_id: string
          escalation_level: number
          id: string
          last_escalated_at: string | null
          notes: string | null
          resolution_reason: string | null
          resolved_at: string | null
          resolved_by: string | null
          responding_at: string | null
          responding_by: string | null
          status: Database["public"]["Enums"]["emergency_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          created_at?: string
          emergency_event_id: string
          escalation_level?: number
          id?: string
          last_escalated_at?: string | null
          notes?: string | null
          resolution_reason?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          responding_at?: string | null
          responding_by?: string | null
          status?: Database["public"]["Enums"]["emergency_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          created_at?: string
          emergency_event_id?: string
          escalation_level?: number
          id?: string
          last_escalated_at?: string | null
          notes?: string | null
          resolution_reason?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          responding_at?: string | null
          responding_by?: string | null
          status?: Database["public"]["Enums"]["emergency_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      ai_query_log: {
        Row: {
          actor_profile_id: string
          created_at: string
          id: string
          insight_kind: Database["public"]["Enums"]["insight_kind"]
          matched_intent: string | null
          query_text: string
          response_text: string | null
          tenant_id: string
          tool_calls: Json
        }
        Insert: {
          actor_profile_id: string
          created_at?: string
          id?: string
          insight_kind?: Database["public"]["Enums"]["insight_kind"]
          matched_intent?: string | null
          query_text: string
          response_text?: string | null
          tenant_id: string
          tool_calls?: Json
        }
        Update: {
          actor_profile_id?: string
          created_at?: string
          id?: string
          insight_kind?: Database["public"]["Enums"]["insight_kind"]
          matched_intent?: string | null
          query_text?: string
          response_text?: string | null
          tenant_id?: string
          tool_calls?: Json
        }
        Relationships: []
      }
      shift_recommendations: {
        Row: {
          candidate_employee_id: string
          decided_at: string | null
          decided_by: string | null
          ends_at: string
          generated_at: string
          id: string
          published_shift_id: string | null
          reasons: Json
          score: number
          shift_date: string
          site_id: string
          starts_at: string
          status: Database["public"]["Enums"]["shift_recommendation_status"]
          tenant_id: string
        }
        Insert: {
          candidate_employee_id: string
          decided_at?: string | null
          decided_by?: string | null
          ends_at: string
          generated_at?: string
          id?: string
          published_shift_id?: string | null
          reasons?: Json
          score: number
          shift_date: string
          site_id: string
          starts_at: string
          status?: Database["public"]["Enums"]["shift_recommendation_status"]
          tenant_id: string
        }
        Update: {
          candidate_employee_id?: string
          decided_at?: string | null
          decided_by?: string | null
          ends_at?: string
          generated_at?: string
          id?: string
          published_shift_id?: string | null
          reasons?: Json
          score?: number
          shift_date?: string
          site_id?: string
          starts_at?: string
          status?: Database["public"]["Enums"]["shift_recommendation_status"]
          tenant_id?: string
        }
        Relationships: []
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
        Args: {
          p_accuracy_meters?: number
          p_client_captured_at?: string
          p_device_context?: Json
          p_employee_id: string
          p_gps_denied?: boolean
          p_latitude?: number
          p_longitude?: number
          p_offline_captured?: boolean
          p_shift_id?: string
          p_site_id: string
        }
        Returns: {
          clock_in_at: string | null
          clock_out_at: string | null
          created_at: string
          early_departure_minutes: number | null
          employee_id: string
          gps_verification_status: Database["public"]["Enums"]["gps_verification_status"]
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
        Args: {
          p_accuracy_meters?: number
          p_attendance_record_id: string
          p_client_captured_at?: string
          p_device_context?: Json
          p_gps_denied?: boolean
          p_latitude?: number
          p_longitude?: number
          p_offline_captured?: boolean
        }
        Returns: {
          clock_in_at: string | null
          clock_out_at: string | null
          created_at: string
          early_departure_minutes: number | null
          employee_id: string
          gps_verification_status: Database["public"]["Enums"]["gps_verification_status"]
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
      get_operational_metrics: {
        Args: { p_tenant_id: string; p_period_start: string; p_period_end: string }
        Returns: {
          active_employee_count: number
          attendance_rate_pct: number
          late_attendance_count: number
          pending_leave_requests: number
          approved_leave_days: number
          task_completion_rate_pct: number
          overdue_task_count: number
          open_incident_count: number
          critical_incident_count: number
          active_asset_count: number
          assets_in_maintenance_count: number
          active_contract_count: number
          contracts_expiring_count: number
          qualifications_expiring_count: number
          trainings_completed_count: number
        }[]
      }
      set_employee_skill: {
        Args: { p_employee_id: string; p_skill_id: string; p_proficiency_level: Database["public"]["Enums"]["proficiency_level"] }
        Returns: Database["public"]["Tables"]["employee_skills"]["Row"]
      }
      verify_employee_skill: {
        Args: { p_employee_skill_id: string }
        Returns: Database["public"]["Tables"]["employee_skills"]["Row"]
      }
      upsert_employee_qualification: {
        Args: {
          p_id: string | null
          p_employee_id: string
          p_credential_type: Database["public"]["Enums"]["credential_type"]
          p_name: string
          p_issuing_organization?: string | null
          p_issue_date?: string | null
          p_expiry_date?: string | null
          p_evidence_document_id?: string | null
        }
        Returns: Database["public"]["Tables"]["employee_qualifications"]["Row"]
      }
      verify_employee_qualification: {
        Args: { p_id: string; p_approve: boolean }
        Returns: Database["public"]["Tables"]["employee_qualifications"]["Row"]
      }
      sync_expired_qualifications: {
        Args: { p_tenant_id: string }
        Returns: Database["public"]["Tables"]["employee_qualifications"]["Row"][]
      }
      enroll_employee_training: {
        Args: { p_training_program_id: string; p_employee_id: string }
        Returns: Database["public"]["Tables"]["training_enrollments"]["Row"]
      }
      complete_employee_training: {
        Args: { p_enrollment_id: string; p_status: Database["public"]["Enums"]["training_enrollment_status"]; p_result?: string | null }
        Returns: Database["public"]["Tables"]["training_enrollments"]["Row"]
      }
      create_performance_review: {
        Args: { p_employee_id: string; p_reviewer_profile_id: string; p_review_period_start: string; p_review_period_end: string }
        Returns: Database["public"]["Tables"]["performance_reviews"]["Row"]
      }
      advance_performance_review: {
        Args: {
          p_review_id: string
          p_new_status: Database["public"]["Enums"]["performance_review_status"]
          p_manager_comments?: string | null
          p_employee_comments?: string | null
          p_overall_rating?: number | null
        }
        Returns: Database["public"]["Tables"]["performance_reviews"]["Row"]
      }
      add_development_action: {
        Args: { p_employee_id: string; p_goal: string; p_owner_profile_id?: string | null; p_target_date?: string | null; p_review_id?: string | null }
        Returns: Database["public"]["Tables"]["development_actions"]["Row"]
      }
      update_development_action_status: {
        Args: { p_id: string; p_status: string }
        Returns: Database["public"]["Tables"]["development_actions"]["Row"]
      }
      compute_sla_measurement: {
        Args: { p_sla_definition_id: string; p_period_start: string; p_period_end: string }
        Returns: Database["public"]["Tables"]["sla_measurements"]["Row"]
      }
      create_contract_document_slot: {
        Args: {
          p_contract_id: string
          p_file_name: string
          p_mime_type: string
          p_file_size_bytes: number
        }
        Returns: Database["public"]["Tables"]["contract_documents"]["Row"]
      }
      create_task_template_from_scope_item: {
        Args: {
          p_scope_of_work_item_id: string
          p_default_assignee_id?: string | null
          p_default_team_id?: string | null
        }
        Returns: Database["public"]["Tables"]["task_templates"]["Row"]
      }
      recompute_quote_totals: {
        Args: { p_quote_id: string }
        Returns: Database["public"]["Tables"]["quotes"]["Row"]
      }
      convert_quote_to_contract: {
        Args: {
          p_quote_id: string
          p_contract_number: string
          p_start_date: string
        }
        Returns: Database["public"]["Tables"]["contracts"]["Row"]
      }
      assign_asset: {
        Args: {
          p_asset_id: string
          p_assigned_to_employee_id?: string | null
          p_assigned_to_team_id?: string | null
          p_assigned_to_site_id?: string | null
          p_condition?: string | null
          p_reason?: string | null
        }
        Returns: Database["public"]["Tables"]["assets"]["Row"]
      }
      return_asset: {
        Args: {
          p_asset_id: string
          p_condition_at_return?: string | null
          p_new_status?: Database["public"]["Enums"]["asset_status"]
        }
        Returns: Database["public"]["Tables"]["assets"]["Row"]
      }
      transition_asset_status: {
        Args: { p_asset_id: string; p_new_status: Database["public"]["Enums"]["asset_status"] }
        Returns: Database["public"]["Tables"]["assets"]["Row"]
      }
      record_asset_maintenance: {
        Args: {
          p_asset_id: string
          p_description: string
          p_cost?: number | null
          p_performed_at?: string
        }
        Returns: Database["public"]["Tables"]["asset_maintenance_records"]["Row"]
      }
      record_inventory_movement: {
        Args: {
          p_item_id: string
          p_site_id: string
          p_movement_type: Database["public"]["Enums"]["inventory_movement_type"]
          p_quantity: number
          p_reference?: string | null
          p_allow_negative?: boolean
        }
        Returns: Database["public"]["Tables"]["inventory_movements"]["Row"]
      }
      get_inventory_balance: {
        Args: { p_item_id: string; p_site_id: string }
        Returns: number
      }
      submit_procurement_request: {
        Args: {
          p_tenant_id: string
          p_item_description: string
          p_quantity: number
          p_site_id?: string | null
          p_estimated_cost?: number | null
        }
        Returns: Database["public"]["Tables"]["procurement_requests"]["Row"]
      }
      decide_procurement_request: {
        Args: { p_request_id: string; p_approve: boolean; p_rejected_reason?: string | null }
        Returns: Database["public"]["Tables"]["procurement_requests"]["Row"]
      }
      advance_procurement_request: {
        Args: { p_request_id: string; p_new_status: Database["public"]["Enums"]["procurement_status"] }
        Returns: Database["public"]["Tables"]["procurement_requests"]["Row"]
      }
      report_incident: {
        Args: {
          p_tenant_id: string
          p_category: Database["public"]["Enums"]["incident_category"]
          p_severity: Database["public"]["Enums"]["incident_severity"]
          p_occurred_at: string
          p_description: string
          p_site_id?: string | null
          p_contract_id?: string | null
        }
        Returns: Database["public"]["Tables"]["incidents"]["Row"]
      }
      link_incident_employee: {
        Args: { p_incident_id: string; p_employee_id: string; p_involvement?: string }
        Returns: Database["public"]["Tables"]["incident_affected_employees"]["Row"]
      }
      transition_incident_status: {
        Args: {
          p_incident_id: string
          p_new_status: Database["public"]["Enums"]["incident_status"]
          p_notes?: string | null
        }
        Returns: Database["public"]["Tables"]["incidents"]["Row"]
      }
      add_incident_action: {
        Args: {
          p_incident_id: string
          p_description: string
          p_owner_profile_id?: string | null
          p_due_date?: string | null
        }
        Returns: Database["public"]["Tables"]["incident_actions"]["Row"]
      }
      complete_incident_action: {
        Args: { p_action_id: string }
        Returns: Database["public"]["Tables"]["incident_actions"]["Row"]
      }
      verify_incident_action: {
        Args: { p_action_id: string }
        Returns: Database["public"]["Tables"]["incident_actions"]["Row"]
      }
      upsert_compliance_record: {
        Args: {
          p_id: string | null
          p_requirement_id: string
          p_site_id?: string | null
          p_client_id?: string | null
          p_contract_id?: string | null
          p_responsible_profile_id?: string | null
          p_due_date?: string | null
          p_expiry_date?: string | null
          p_evidence_storage_path?: string | null
          p_notes?: string | null
        }
        Returns: Database["public"]["Tables"]["compliance_records"]["Row"]
      }
      verify_compliance_record: {
        Args: { p_id: string; p_approve: boolean }
        Returns: Database["public"]["Tables"]["compliance_records"]["Row"]
      }
      sync_expired_compliance_records: {
        Args: { p_tenant_id: string }
        Returns: Database["public"]["Tables"]["compliance_records"]["Row"][]
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
      create_document_upload_slot: {
        Args: {
          p_document_type: Database["public"]["Enums"]["document_type"]
          p_employee_id: string
          p_expiry_date?: string
          p_file_name: string
          p_file_size_bytes: number
          p_mime_type: string
        }
        Returns: {
          created_at: string
          document_type: Database["public"]["Enums"]["document_type"]
          employee_id: string
          expiry_date: string | null
          file_name: string
          file_size_bytes: number
          id: string
          mime_type: string
          review_notes: string | null
          status: Database["public"]["Enums"]["document_status"]
          storage_path: string
          supersedes_document_id: string | null
          tenant_id: string
          updated_at: string
          uploaded_by: string | null
          verified_at: string | null
          verified_by: string | null
          version: number
        }
        SetofOptions: { from: "*"; to: "employee_documents"; isOneToOne: true; isSetofReturn: false }
      }
      verify_document: {
        Args: { p_approve: boolean; p_document_id: string; p_review_notes?: string }
        Returns: {
          created_at: string
          document_type: Database["public"]["Enums"]["document_type"]
          employee_id: string
          expiry_date: string | null
          file_name: string
          file_size_bytes: number
          id: string
          mime_type: string
          review_notes: string | null
          status: Database["public"]["Enums"]["document_status"]
          storage_path: string
          supersedes_document_id: string | null
          tenant_id: string
          updated_at: string
          uploaded_by: string | null
          verified_at: string | null
          verified_by: string | null
          version: number
        }
        SetofOptions: { from: "*"; to: "employee_documents"; isOneToOne: true; isSetofReturn: false }
      }
      replace_document: {
        Args: {
          p_expiry_date?: string
          p_file_name: string
          p_file_size_bytes: number
          p_mime_type: string
          p_old_document_id: string
        }
        Returns: {
          created_at: string
          document_type: Database["public"]["Enums"]["document_type"]
          employee_id: string
          expiry_date: string | null
          file_name: string
          file_size_bytes: number
          id: string
          mime_type: string
          review_notes: string | null
          status: Database["public"]["Enums"]["document_status"]
          storage_path: string
          supersedes_document_id: string | null
          tenant_id: string
          updated_at: string
          uploaded_by: string | null
          verified_at: string | null
          verified_by: string | null
          version: number
        }
        SetofOptions: { from: "*"; to: "employee_documents"; isOneToOne: true; isSetofReturn: false }
      }
      sync_expired_documents: {
        Args: { p_tenant_id: string }
        Returns: {
          created_at: string
          document_type: Database["public"]["Enums"]["document_type"]
          employee_id: string
          expiry_date: string | null
          file_name: string
          file_size_bytes: number
          id: string
          mime_type: string
          review_notes: string | null
          status: Database["public"]["Enums"]["document_status"]
          storage_path: string
          supersedes_document_id: string | null
          tenant_id: string
          updated_at: string
          uploaded_by: string | null
          verified_at: string | null
          verified_by: string | null
          version: number
        }[]
        SetofOptions: { from: "*"; to: "employee_documents"; isOneToOne: false; isSetofReturn: true }
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
      request_attendance_location_exception: {
        Args: { p_attendance_record_id: string; p_reason: string }
        Returns: {
          attendance_record_id: string
          created_at: string
          employee_id: string
          id: string
          reason: string
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          tenant_id: string
          updated_at: string
        }
      }
      decide_attendance_location_exception: {
        Args: { p_approve: boolean; p_exception_id: string; p_review_notes?: string }
        Returns: {
          attendance_record_id: string
          created_at: string
          employee_id: string
          id: string
          reason: string
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          tenant_id: string
          updated_at: string
        }
      }
      start_patrol: {
        Args: { p_patrol_route_id: string }
        Returns: {
          completed_at: string | null
          created_at: string
          employee_id: string
          expected_checkpoint_count: number
          id: string
          patrol_route_id: string
          scanned_checkpoint_count: number
          site_id: string
          started_at: string
          status: Database["public"]["Enums"]["patrol_run_status"]
          tenant_id: string
        }
      }
      scan_checkpoint: {
        Args: {
          p_checkpoint_code: string
          p_latitude?: number
          p_longitude?: number
          p_patrol_run_id: string
          p_scan_method?: Database["public"]["Enums"]["checkpoint_scan_type"]
        }
        Returns: {
          run: {
            completed_at: string | null
            created_at: string
            employee_id: string
            expected_checkpoint_count: number
            id: string
            patrol_route_id: string
            scanned_checkpoint_count: number
            site_id: string
            started_at: string
            status: Database["public"]["Enums"]["patrol_run_status"]
            tenant_id: string
          }
          scan: {
            checkpoint_id: string | null
            employee_id: string
            id: string
            latitude: number | null
            longitude: number | null
            patrol_run_id: string
            risk_flags: Json
            scan_method: Database["public"]["Enums"]["checkpoint_scan_type"]
            scanned_at: string
            scanned_code: string | null
            sequence_number: number
            tenant_id: string
            verification_result: Database["public"]["Enums"]["checkpoint_scan_result"]
          }
        }[]
      }
      complete_patrol: {
        Args: { p_patrol_run_id: string }
        Returns: {
          completed_at: string | null
          created_at: string
          employee_id: string
          expected_checkpoint_count: number
          id: string
          patrol_route_id: string
          scanned_checkpoint_count: number
          site_id: string
          started_at: string
          status: Database["public"]["Enums"]["patrol_run_status"]
          tenant_id: string
        }
      }
      get_patrol_summary: {
        Args: { p_since?: string; p_tenant_id: string }
        Returns: {
          active_patrols: number
          completed_patrols: number
          exception_rate: number
          incomplete_patrols: number
          late_checkpoints: number
          missed_checkpoints: number
        }[]
      }
      get_command_centre_snapshot: {
        Args: { p_tenant_id: string }
        Returns: {
          alerts_critical: number
          alerts_open: number
          compliance_expired: number
          compliance_expiring_soon: number
          contracts_active: number
          contracts_sla_breaching: number
          emergencies_active: number
          incidents_critical: number
          incidents_open: number
          incidents_overdue: number
          patrols_active: number
          patrols_completed_today: number
          patrols_missed: number
          sites_total_active: number
          sites_uncovered: number
          sites_understaffed: number
          tasks_overdue: number
          tasks_verification_pending: number
          workforce_absent: number
          workforce_clocked_in: number
          workforce_late: number
          workforce_pending_exceptions: number
          workforce_total_scheduled: number
        }[]
      }
      acknowledge_operational_alert: {
        Args: { p_alert_id: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          alert_type: Database["public"]["Enums"]["operational_alert_type"]
          contract_id: string | null
          created_at: string
          employee_id: string | null
          id: string
          message: string
          resolution_notes: string | null
          resolved_at: string | null
          resolved_by: string | null
          severity: Database["public"]["Enums"]["alert_severity"]
          site_id: string | null
          status: Database["public"]["Enums"]["alert_status"]
          tenant_id: string
          updated_at: string
        }
      }
      resolve_operational_alert: {
        Args: { p_alert_id: string; p_resolution_notes?: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          alert_type: Database["public"]["Enums"]["operational_alert_type"]
          contract_id: string | null
          created_at: string
          employee_id: string | null
          id: string
          message: string
          resolution_notes: string | null
          resolved_at: string | null
          resolved_by: string | null
          severity: Database["public"]["Enums"]["alert_severity"]
          site_id: string | null
          status: Database["public"]["Enums"]["alert_status"]
          tenant_id: string
          updated_at: string
        }
      }
      reopen_operational_alert: {
        Args: { p_alert_id: string; p_reason: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          alert_type: Database["public"]["Enums"]["operational_alert_type"]
          contract_id: string | null
          created_at: string
          employee_id: string | null
          id: string
          message: string
          resolution_notes: string | null
          resolved_at: string | null
          resolved_by: string | null
          severity: Database["public"]["Enums"]["alert_severity"]
          site_id: string | null
          status: Database["public"]["Enums"]["alert_status"]
          tenant_id: string
          updated_at: string
        }
      }
      trigger_emergency: {
        Args: {
          p_accuracy_meters?: number
          p_device_context?: Json
          p_emergency_type?: Database["public"]["Enums"]["emergency_type"]
          p_latitude?: number
          p_longitude?: number
          p_site_id?: string
        }
        Returns: {
          accuracy_meters: number | null
          device_context: Json
          emergency_type: Database["public"]["Enums"]["emergency_type"]
          employee_id: string
          id: string
          latitude: number | null
          longitude: number | null
          shift_id: string | null
          site_id: string | null
          tenant_id: string
          triggered_at: string
        }
      }
      acknowledge_emergency: {
        Args: { p_emergency_event_id: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          created_at: string
          emergency_event_id: string
          escalation_level: number
          id: string
          last_escalated_at: string | null
          notes: string | null
          resolution_reason: string | null
          resolved_at: string | null
          resolved_by: string | null
          responding_at: string | null
          responding_by: string | null
          status: Database["public"]["Enums"]["emergency_status"]
          tenant_id: string
          updated_at: string
        }
      }
      respond_to_emergency: {
        Args: { p_emergency_event_id: string; p_notes?: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          created_at: string
          emergency_event_id: string
          escalation_level: number
          id: string
          last_escalated_at: string | null
          notes: string | null
          resolution_reason: string | null
          resolved_at: string | null
          resolved_by: string | null
          responding_at: string | null
          responding_by: string | null
          status: Database["public"]["Enums"]["emergency_status"]
          tenant_id: string
          updated_at: string
        }
      }
      resolve_emergency: {
        Args: { p_emergency_event_id: string; p_resolution_reason: string }
        Returns: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          created_at: string
          emergency_event_id: string
          escalation_level: number
          id: string
          last_escalated_at: string | null
          notes: string | null
          resolution_reason: string | null
          resolved_at: string | null
          resolved_by: string | null
          responding_at: string | null
          responding_by: string | null
          status: Database["public"]["Enums"]["emergency_status"]
          tenant_id: string
          updated_at: string
        }
      }
      log_ai_query: {
        Args: {
          p_insight_kind?: Database["public"]["Enums"]["insight_kind"]
          p_matched_intent: string
          p_query_text: string
          p_response_text: string
          p_tool_calls: Json
        }
        Returns: {
          actor_profile_id: string
          created_at: string
          id: string
          insight_kind: Database["public"]["Enums"]["insight_kind"]
          matched_intent: string | null
          query_text: string
          response_text: string | null
          tenant_id: string
          tool_calls: Json
        }
      }
      get_understaffed_sites: {
        Args: { p_tenant_id: string }
        Returns: {
          assigned_count: number
          required_count: number
          shortfall: number
          site_id: string
          site_name: string
        }[]
      }
      get_employees_absent_now: {
        Args: { p_tenant_id: string }
        Returns: {
          employee_id: string
          employee_name: string
          minutes_overdue: number
          shift_starts_at: string
          site_id: string
          site_name: string
        }[]
      }
      get_expiring_qualifications: {
        Args: { p_tenant_id: string; p_within_days?: number }
        Returns: {
          days_remaining: number
          employee_id: string
          employee_name: string
          expiry_date: string
          qualification_name: string
        }[]
      }
      get_declining_sla_contracts: {
        Args: { p_tenant_id: string }
        Returns: {
          contract_id: string
          contract_number: string
          latest_value: number
          period_end: string
          sla_name: string
          target_met: boolean
          target_value: number
        }[]
      }
      get_overtime_spike_employees: {
        Args: { p_since?: string; p_tenant_id: string }
        Returns: {
          employee_id: string
          employee_name: string
          record_count: number
          total_overtime_minutes: number
        }[]
      }
      get_site_incident_ranking: {
        Args: { p_since?: string; p_tenant_id: string }
        Returns: {
          critical_count: number
          incident_count: number
          site_id: string
          site_name: string
        }[]
      }
      generate_shift_recommendations: {
        Args: { p_ends_at: string; p_shift_date: string; p_site_id: string; p_starts_at: string }
        Returns: {
          candidate_employee_id: string
          decided_at: string | null
          decided_by: string | null
          ends_at: string
          generated_at: string
          id: string
          published_shift_id: string | null
          reasons: Json
          score: number
          shift_date: string
          site_id: string
          starts_at: string
          status: Database["public"]["Enums"]["shift_recommendation_status"]
          tenant_id: string
        }[]
      }
      decide_shift_recommendation: {
        Args: { p_accept: boolean; p_recommendation_id: string }
        Returns: {
          candidate_employee_id: string
          decided_at: string | null
          decided_by: string | null
          ends_at: string
          generated_at: string
          id: string
          published_shift_id: string | null
          reasons: Json
          score: number
          shift_date: string
          site_id: string
          starts_at: string
          status: Database["public"]["Enums"]["shift_recommendation_status"]
          tenant_id: string
        }
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
      asset_status:
        | "available"
        | "assigned"
        | "maintenance"
        | "lost"
        | "damaged"
        | "retired"
        | "disposed"
      attendance_correction_status: "pending" | "approved" | "rejected"
      credential_type: "qualification" | "certification"
      credential_status: "pending_verification" | "verified" | "expired" | "revoked"
      proficiency_level: "beginner" | "intermediate" | "advanced" | "expert"
      training_enrollment_status: "scheduled" | "in_progress" | "completed" | "failed" | "cancelled"
      performance_review_status: "draft" | "manager_review" | "employee_review" | "acknowledgement" | "finalized"
      compliance_status:
        | "pending"
        | "in_progress"
        | "compliant"
        | "non_compliant"
        | "expired"
        | "waived"
      contract_status: "draft" | "active" | "expiring" | "expired" | "suspended" | "terminated"
      contract_billing_frequency: "weekly" | "monthly" | "quarterly" | "annually" | "once_off"
      contract_party_responsibility: "contractor" | "client" | "shared"
      quote_status: "draft" | "sent" | "viewed" | "negotiation" | "approved" | "rejected" | "expired" | "cancelled"
      quote_line_category: "labour" | "consumables" | "equipment" | "transport" | "overhead" | "other"
      document_status:
        | "uploaded"
        | "pending_review"
        | "verified"
        | "rejected"
        | "expired"
        | "archived"
      document_type:
        | "id_document"
        | "qualification"
        | "contract"
        | "certificate"
        | "training_record"
        | "medical"
        | "disciplinary"
        | "other"
      employment_status: "active" | "on_leave" | "suspended" | "terminated"
      employment_type: "full_time" | "part_time" | "contract" | "temporary"
      entity_status: "active" | "inactive" | "onboarding" | "offboarded"
      incident_action_status: "open" | "in_progress" | "completed" | "verified"
      incident_category:
        | "workplace_safety"
        | "property_damage"
        | "client_incident"
        | "near_miss"
        | "security"
        | "operational_other"
      incident_severity: "low" | "medium" | "high" | "critical"
      inventory_movement_type:
        | "receipt"
        | "issue"
        | "transfer_in"
        | "transfer_out"
        | "adjustment"
        | "return"
      incident_status:
        | "reported"
        | "acknowledged"
        | "investigating"
        | "corrective_action"
        | "pending_closure"
        | "closed"
      leave_status: "pending" | "approved" | "rejected" | "cancelled" | "revoked"
      notification_email_status: "not_sent" | "sent" | "failed"
      organization_status: "pending" | "active" | "inactive" | "suspended"
      procurement_status:
        | "requested"
        | "submitted"
        | "approved"
        | "rejected"
        | "ordered"
        | "received"
        | "completed"
        | "cancelled"
      profile_status: "active" | "inactive" | "suspended"
      shift_status: "scheduled" | "confirmed" | "cancelled" | "completed"
      sla_metric_type:
        | "staffing_fulfillment"
        | "task_completion_rate"
        | "incident_response_hours"
        | "compliance_completion_rate"
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
      gps_verification_status:
        | "verified"
        | "outside_geofence"
        | "low_accuracy"
        | "location_unavailable"
        | "pending_verification"
        | "offline_pending"
        | "manual_review"
        | "not_applicable"
      checkpoint_scan_type: "qr" | "nfc" | "manual"
      patrol_run_status: "in_progress" | "completed" | "incomplete" | "abandoned"
      checkpoint_scan_result:
        | "valid"
        | "wrong_sequence"
        | "duplicate"
        | "out_of_window"
        | "invalid_checkpoint"
        | "not_assigned"
      alert_severity: "info" | "warning" | "critical"
      alert_status: "open" | "acknowledged" | "resolved"
      operational_alert_type:
        | "site_understaffed"
        | "employee_absent"
        | "employee_late"
        | "patrol_missed"
        | "checkpoint_missed"
        | "qualification_expired"
        | "contract_sla_breach"
        | "incident_overdue"
        | "critical_task_overdue"
        | "excessive_overtime"
        | "emergency_active"
      emergency_type: "panic" | "medical" | "security_threat" | "other"
      emergency_status: "triggered" | "acknowledged" | "responding" | "resolved"
      insight_kind: "rule_based" | "ai_generated"
      shift_recommendation_status: "suggested" | "accepted" | "rejected" | "published"
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
      contract_status: ["draft", "active", "expiring", "expired", "suspended", "terminated"],
      contract_billing_frequency: ["weekly", "monthly", "quarterly", "annually", "once_off"],
      contract_party_responsibility: ["contractor", "client", "shared"],
      quote_status: ["draft", "sent", "viewed", "negotiation", "approved", "rejected", "expired", "cancelled"],
      quote_line_category: ["labour", "consumables", "equipment", "transport", "overhead", "other"],
      document_status: [
        "uploaded",
        "pending_review",
        "verified",
        "rejected",
        "expired",
        "archived",
      ],
      document_type: [
        "id_document",
        "qualification",
        "contract",
        "certificate",
        "training_record",
        "medical",
        "disciplinary",
        "other",
      ],
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

