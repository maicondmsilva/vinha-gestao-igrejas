export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      membership_unit_access: {
        Row: {
          access_level: Database["public"]["Enums"]["unit_access_level"]
          created_at: string
          include_children: boolean
          membership_id: string
          unit_id: string
        }
        Insert: {
          access_level?: Database["public"]["Enums"]["unit_access_level"]
          created_at?: string
          include_children?: boolean
          membership_id: string
          unit_id: string
        }
        Update: {
          access_level?: Database["public"]["Enums"]["unit_access_level"]
          created_at?: string
          include_children?: boolean
          membership_id?: string
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "membership_unit_access_membership_id_fkey"
            columns: ["membership_id"]
            isOneToOne: false
            referencedRelation: "organization_memberships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "membership_unit_access_unit_id_fkey"
            columns: ["unit_id"]
            isOneToOne: false
            referencedRelation: "organization_units"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_memberships: {
        Row: {
          created_at: string
          default_unit_id: string | null
          id: string
          organization_id: string
          role: Database["public"]["Enums"]["membership_role"]
          status: Database["public"]["Enums"]["membership_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          default_unit_id?: string | null
          id?: string
          organization_id: string
          role?: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          default_unit_id?: string | null
          id?: string
          organization_id?: string
          role?: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_memberships_default_unit_id_organization_id_fkey"
            columns: ["default_unit_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_units"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "organization_memberships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_units: {
        Row: {
          address: Json
          created_at: string
          id: string
          name: string
          organization_id: string
          parent_unit_id: string | null
          slug: string
          status: Database["public"]["Enums"]["organization_status"]
          unit_type: Database["public"]["Enums"]["unit_type"]
          updated_at: string
        }
        Insert: {
          address?: Json
          created_at?: string
          id?: string
          name: string
          organization_id: string
          parent_unit_id?: string | null
          slug: string
          status?: Database["public"]["Enums"]["organization_status"]
          unit_type?: Database["public"]["Enums"]["unit_type"]
          updated_at?: string
        }
        Update: {
          address?: Json
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          parent_unit_id?: string | null
          slug?: string
          status?: Database["public"]["Enums"]["organization_status"]
          unit_type?: Database["public"]["Enums"]["unit_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_units_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_units_parent_unit_id_fkey"
            columns: ["parent_unit_id"]
            isOneToOne: false
            referencedRelation: "organization_units"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          id: string
          legal_name: string | null
          name: string
          primary_color: string
          slug: string
          status: Database["public"]["Enums"]["organization_status"]
          tax_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          legal_name?: string | null
          name: string
          primary_color?: string
          slug: string
          status?: Database["public"]["Enums"]["organization_status"]
          tax_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          legal_name?: string | null
          name?: string
          primary_color?: string
          slug?: string
          status?: Database["public"]["Enums"]["organization_status"]
          tax_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      platform_operators: {
        Row: {
          active: boolean
          created_at: string
          full_name: string
          role: Database["public"]["Enums"]["platform_operator_role"]
          updated_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          full_name: string
          role?: Database["public"]["Enums"]["platform_operator_role"]
          updated_at?: string
          user_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          full_name?: string
          role?: Database["public"]["Enums"]["platform_operator_role"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          phone: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id: string
          phone?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      user_access_preferences: {
        Row: {
          selected_organization_id: string | null
          selected_unit_id: string | null
          theme: string
          updated_at: string
          user_id: string
        }
        Insert: {
          selected_organization_id?: string | null
          selected_unit_id?: string | null
          theme?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          selected_organization_id?: string | null
          selected_unit_id?: string | null
          theme?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_access_preferences_selected_organization_id_fkey"
            columns: ["selected_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_access_preferences_selected_unit_id_fkey"
            columns: ["selected_unit_id"]
            isOneToOne: false
            referencedRelation: "organization_units"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      access_context: { Args: never; Returns: Json }
      bootstrap_organization: {
        Args: {
          p_full_name?: string
          p_headquarters_name: string
          p_organization_name: string
          p_organization_slug: string
        }
        Returns: string
      }
      bootstrap_platform_owner: {
        Args: { p_full_name: string }
        Returns: {
          active: boolean
          full_name: string
          role: Database["public"]["Enums"]["platform_operator_role"]
          user_id: string
        }[]
      }
      platform_operator_context: {
        Args: never
        Returns: {
          active: boolean
          full_name: string
          role: Database["public"]["Enums"]["platform_operator_role"]
          user_id: string
        }[]
      }
      set_access_context: {
        Args: {
          organization_id: string
          selected_theme?: string
          unit_id?: string
        }
        Returns: undefined
      }
    }
    Enums: {
      membership_role:
        | "owner"
        | "pastor"
        | "admin"
        | "secretary"
        | "finance"
        | "leader"
        | "member"
        | "viewer"
      membership_status: "pending" | "active" | "suspended" | "revoked"
      organization_status: "active" | "trial" | "suspended" | "cancelled"
      platform_operator_role: "owner" | "admin" | "support" | "read_only"
      unit_access_level: "read" | "manage" | "admin"
      unit_type:
        | "headquarters"
        | "campus"
        | "congregation"
        | "regional"
        | "branch"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      membership_role: [
        "owner",
        "pastor",
        "admin",
        "secretary",
        "finance",
        "leader",
        "member",
        "viewer",
      ],
      membership_status: ["pending", "active", "suspended", "revoked"],
      organization_status: ["active", "trial", "suspended", "cancelled"],
      platform_operator_role: ["owner", "admin", "support", "read_only"],
      unit_access_level: ["read", "manage", "admin"],
      unit_type: [
        "headquarters",
        "campus",
        "congregation",
        "regional",
        "branch",
      ],
    },
  },
} as const

