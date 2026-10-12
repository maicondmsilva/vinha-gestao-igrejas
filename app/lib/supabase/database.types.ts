
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {

  "public": {
          Tables: {
            "emergency_contacts": {
                  Row: {
                    "created_at": string,"id": string,"name": string,"organization_id": string,"person_id": string,"phone": string,"relationship": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"name": string,"organization_id": string,"person_id": string,"phone": string,"relationship"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"name"?: string,"organization_id"?: string,"person_id"?: string,"phone"?: string,"relationship"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "emergency_contacts_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "emergency_contacts_person_id_organization_id_fkey"
      columns: ["person_id","organization_id"]
isOneToOne: false
      referencedRelation: "people"
      referencedColumns: ["id","organization_id"]
    }
                  ]
                },"membership_unit_access": {
                  Row: {
                    "access_level": Database["public"]['Enums']["unit_access_level"],"created_at": string,"include_children": boolean,"membership_id": string,"unit_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "access_level"?: Database["public"]['Enums']["unit_access_level"],"created_at"?: string,"include_children"?: boolean,"membership_id": string,"unit_id": string
                  }
                  Update: {
                    "access_level"?: Database["public"]['Enums']["unit_access_level"],"created_at"?: string,"include_children"?: boolean,"membership_id"?: string,"unit_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "membership_unit_access_membership_id_fkey"
      columns: ["membership_id"]
isOneToOne: false
      referencedRelation: "organization_memberships"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "membership_unit_access_unit_id_fkey"
      columns: ["unit_id"]
isOneToOne: false
      referencedRelation: "organization_units"
      referencedColumns: ["id"]
    }
                  ]
                },"organization_memberships": {
                  Row: {
                    "created_at": string,"default_unit_id": string | null,"id": string,"organization_id": string,"role": Database["public"]['Enums']["membership_role"],"status": Database["public"]['Enums']["membership_status"],"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"default_unit_id"?: string | null,"id"?: string,"organization_id": string,"role"?: Database["public"]['Enums']["membership_role"],"status"?: Database["public"]['Enums']["membership_status"],"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"default_unit_id"?: string | null,"id"?: string,"organization_id"?: string,"role"?: Database["public"]['Enums']["membership_role"],"status"?: Database["public"]['Enums']["membership_status"],"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "organization_memberships_default_unit_id_organization_id_fkey"
      columns: ["default_unit_id","organization_id"]
isOneToOne: false
      referencedRelation: "organization_units"
      referencedColumns: ["id","organization_id"]
    },{
      foreignKeyName: "organization_memberships_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"organization_units": {
                  Row: {
                    "address": NonNullable<Json>,"branding_autonomy": boolean,"communication_autonomy": boolean,"created_at": string,"email": string | null,"financial_autonomy": boolean,"id": string,"legal_name": string | null,"name": string,"organization_id": string,"parent_unit_id": string | null,"pastor_name": string | null,"phone": string | null,"slug": string,"status": Database["public"]['Enums']["organization_status"],"tax_id": string | null,"unit_type": Database["public"]['Enums']["unit_type"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address"?: NonNullable<Json>,"branding_autonomy"?: boolean,"communication_autonomy"?: boolean,"created_at"?: string,"email"?: string | null,"financial_autonomy"?: boolean,"id"?: string,"legal_name"?: string | null,"name": string,"organization_id": string,"parent_unit_id"?: string | null,"pastor_name"?: string | null,"phone"?: string | null,"slug": string,"status"?: Database["public"]['Enums']["organization_status"],"tax_id"?: string | null,"unit_type"?: Database["public"]['Enums']["unit_type"],"updated_at"?: string
                  }
                  Update: {
                    "address"?: NonNullable<Json>,"branding_autonomy"?: boolean,"communication_autonomy"?: boolean,"created_at"?: string,"email"?: string | null,"financial_autonomy"?: boolean,"id"?: string,"legal_name"?: string | null,"name"?: string,"organization_id"?: string,"parent_unit_id"?: string | null,"pastor_name"?: string | null,"phone"?: string | null,"slug"?: string,"status"?: Database["public"]['Enums']["organization_status"],"tax_id"?: string | null,"unit_type"?: Database["public"]['Enums']["unit_type"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "organization_units_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "organization_units_parent_same_organization_fkey"
      columns: ["parent_unit_id","organization_id"]
isOneToOne: false
      referencedRelation: "organization_units"
      referencedColumns: ["id","organization_id"]
    },{
      foreignKeyName: "organization_units_parent_unit_id_fkey"
      columns: ["parent_unit_id"]
isOneToOne: false
      referencedRelation: "organization_units"
      referencedColumns: ["id"]
    }
                  ]
                },"organizations": {
                  Row: {
                    "created_at": string,"id": string,"legal_name": string | null,"name": string,"primary_color": string,"slug": string,"status": Database["public"]['Enums']["organization_status"],"tax_id": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"legal_name"?: string | null,"name": string,"primary_color"?: string,"slug": string,"status"?: Database["public"]['Enums']["organization_status"],"tax_id"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"legal_name"?: string | null,"name"?: string,"primary_color"?: string,"slug"?: string,"status"?: Database["public"]['Enums']["organization_status"],"tax_id"?: string | null,"updated_at"?: string
                  }
                  Relationships: [

                  ]
                },"pastoral_notes": {
                  Row: {
                    "author_user_id": string,"content": string,"created_at": string,"id": string,"organization_id": string,"person_id": string,"updated_at": string,"visibility": string
                  }
                  ComputedFields: never
                  Insert: {
                    "author_user_id": string,"content": string,"created_at"?: string,"id"?: string,"organization_id": string,"person_id": string,"updated_at"?: string,"visibility"?: string
                  }
                  Update: {
                    "author_user_id"?: string,"content"?: string,"created_at"?: string,"id"?: string,"organization_id"?: string,"person_id"?: string,"updated_at"?: string,"visibility"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "pastoral_notes_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "pastoral_notes_person_id_organization_id_fkey"
      columns: ["person_id","organization_id"]
isOneToOne: false
      referencedRelation: "people"
      referencedColumns: ["id","organization_id"]
    }
                  ]
                },"people": {
                  Row: {
                    "app_role": string,"auth_user_id": string | null,"baptism_date": string | null,"baptized": boolean,"birth_date": string | null,"cpf": string | null,"created_at": string,"email": string | null,"first_visit_at": string | null,"full_name": string,"gender": string | null,"group_name": string | null,"id": string,"joined_at": string | null,"journey_status": string,"marital_status": string | null,"organization_id": string,"phone": string | null,"photo_path": string | null,"status": string,"tags": (string)[],"unit_id": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "app_role"?: string,"auth_user_id"?: string | null,"baptism_date"?: string | null,"baptized"?: boolean,"birth_date"?: string | null,"cpf"?: string | null,"created_at"?: string,"email"?: string | null,"first_visit_at"?: string | null,"full_name": string,"gender"?: string | null,"group_name"?: string | null,"id"?: string,"joined_at"?: string | null,"journey_status"?: string,"marital_status"?: string | null,"organization_id": string,"phone"?: string | null,"photo_path"?: string | null,"status"?: string,"tags"?: (string)[],"unit_id"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "app_role"?: string,"auth_user_id"?: string | null,"baptism_date"?: string | null,"baptized"?: boolean,"birth_date"?: string | null,"cpf"?: string | null,"created_at"?: string,"email"?: string | null,"first_visit_at"?: string | null,"full_name"?: string,"gender"?: string | null,"group_name"?: string | null,"id"?: string,"joined_at"?: string | null,"journey_status"?: string,"marital_status"?: string | null,"organization_id"?: string,"phone"?: string | null,"photo_path"?: string | null,"status"?: string,"tags"?: (string)[],"unit_id"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "people_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "people_unit_id_organization_id_fkey"
      columns: ["unit_id","organization_id"]
isOneToOne: false
      referencedRelation: "organization_units"
      referencedColumns: ["id","organization_id"]
    }
                  ]
                },"person_addresses": {
                  Row: {
                    "city": string | null,"complement": string | null,"country_code": string,"created_at": string,"district": string | null,"id": string,"number": string | null,"organization_id": string,"person_id": string,"postal_code": string | null,"state": string | null,"street": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "city"?: string | null,"complement"?: string | null,"country_code"?: string,"created_at"?: string,"district"?: string | null,"id"?: string,"number"?: string | null,"organization_id": string,"person_id": string,"postal_code"?: string | null,"state"?: string | null,"street"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "city"?: string | null,"complement"?: string | null,"country_code"?: string,"created_at"?: string,"district"?: string | null,"id"?: string,"number"?: string | null,"organization_id"?: string,"person_id"?: string,"postal_code"?: string | null,"state"?: string | null,"street"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "person_addresses_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "person_addresses_person_id_organization_id_fkey"
      columns: ["person_id","organization_id"]
isOneToOne: false
      referencedRelation: "people"
      referencedColumns: ["id","organization_id"]
    }
                  ]
                },"person_consents": {
                  Row: {
                    "acceptance_snapshot": NonNullable<Json>,"accepted_by_person_id": string | null,"consent_type": string,"created_at": string,"granted": boolean,"granted_at": string | null,"id": string,"ip_address": unknown,"organization_id": string,"person_id": string,"revoked_at": string | null,"source": string,"subject_person_id": string | null,"term_id": string | null,"user_agent": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "acceptance_snapshot"?: NonNullable<Json>,"accepted_by_person_id"?: string | null,"consent_type": string,"created_at"?: string,"granted": boolean,"granted_at"?: string | null,"id"?: string,"ip_address"?: unknown,"organization_id": string,"person_id": string,"revoked_at"?: string | null,"source"?: string,"subject_person_id"?: string | null,"term_id"?: string | null,"user_agent"?: string | null
                  }
                  Update: {
                    "acceptance_snapshot"?: NonNullable<Json>,"accepted_by_person_id"?: string | null,"consent_type"?: string,"created_at"?: string,"granted"?: boolean,"granted_at"?: string | null,"id"?: string,"ip_address"?: unknown,"organization_id"?: string,"person_id"?: string,"revoked_at"?: string | null,"source"?: string,"subject_person_id"?: string | null,"term_id"?: string | null,"user_agent"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "person_consents_accepted_by_person_id_organization_id_fkey"
      columns: ["accepted_by_person_id","organization_id"]
isOneToOne: false
      referencedRelation: "people"
      referencedColumns: ["id","organization_id"]
    },{
      foreignKeyName: "person_consents_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "person_consents_person_id_organization_id_fkey"
      columns: ["person_id","organization_id"]
isOneToOne: false
      referencedRelation: "people"
      referencedColumns: ["id","organization_id"]
    },{
      foreignKeyName: "person_consents_subject_person_id_organization_id_fkey"
      columns: ["subject_person_id","organization_id"]
isOneToOne: false
      referencedRelation: "people"
      referencedColumns: ["id","organization_id"]
    }
                  ]
                },"platform_operator_events": {
                  Row: {
                    "action": string,"actor_user_id": string | null,"created_at": string,"id": number,"invitation_id": string | null,"metadata": NonNullable<Json>,"target_user_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_user_id"?: string | null,"created_at"?: string,"id"?: never,"invitation_id"?: string | null,"metadata"?: NonNullable<Json>,"target_user_id"?: string | null
                  }
                  Update: {
                    "action"?: string,"actor_user_id"?: string | null,"created_at"?: string,"id"?: never,"invitation_id"?: string | null,"metadata"?: NonNullable<Json>,"target_user_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "platform_operator_events_invitation_id_fkey"
      columns: ["invitation_id"]
isOneToOne: false
      referencedRelation: "platform_operator_invites"
      referencedColumns: ["id"]
    }
                  ]
                },"platform_operator_invites": {
                  Row: {
                    "accepted_at": string | null,"created_at": string,"email": string,"expires_at": string,"id": string,"invited_by": string,"revoked_at": string | null,"role": Database["public"]['Enums']["platform_operator_role"],"token": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accepted_at"?: string | null,"created_at"?: string,"email": string,"expires_at"?: string,"id"?: string,"invited_by": string,"revoked_at"?: string | null,"role": Database["public"]['Enums']["platform_operator_role"],"token"?: string
                  }
                  Update: {
                    "accepted_at"?: string | null,"created_at"?: string,"email"?: string,"expires_at"?: string,"id"?: string,"invited_by"?: string,"revoked_at"?: string | null,"role"?: Database["public"]['Enums']["platform_operator_role"],"token"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "platform_operator_invites_invited_by_fkey"
      columns: ["invited_by"]
isOneToOne: false
      referencedRelation: "platform_operators"
      referencedColumns: ["user_id"]
    }
                  ]
                },"platform_operators": {
                  Row: {
                    "active": boolean,"created_at": string,"email": string,"full_name": string,"role": Database["public"]['Enums']["platform_operator_role"],"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"email": string,"full_name": string,"role"?: Database["public"]['Enums']["platform_operator_role"],"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"email"?: string,"full_name"?: string,"role"?: Database["public"]['Enums']["platform_operator_role"],"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [

                  ]
                },"profiles": {
                  Row: {
                    "avatar_url": string | null,"created_at": string,"email": string | null,"full_name": string | null,"id": string,"phone": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "avatar_url"?: string | null,"created_at"?: string,"email"?: string | null,"full_name"?: string | null,"id": string,"phone"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "avatar_url"?: string | null,"created_at"?: string,"email"?: string | null,"full_name"?: string | null,"id"?: string,"phone"?: string | null,"updated_at"?: string
                  }
                  Relationships: [

                  ]
                },"user_access_preferences": {
                  Row: {
                    "selected_organization_id": string | null,"selected_unit_id": string | null,"theme": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "selected_organization_id"?: string | null,"selected_unit_id"?: string | null,"theme"?: string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "selected_organization_id"?: string | null,"selected_unit_id"?: string | null,"theme"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "user_access_preferences_selected_organization_id_fkey"
      columns: ["selected_organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "user_access_preferences_selected_unit_id_fkey"
      columns: ["selected_unit_id"]
isOneToOne: false
      referencedRelation: "organization_units"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "accept_platform_operator_invite":
{ Args: { "p_full_name": string,"p_token": string }; Returns: {
              "active": boolean,"full_name": string,"role": Database["public"]['Enums']["platform_operator_role"],"user_id": string
            }[]
                           },
"access_context":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"bootstrap_organization":
{ Args: { "p_full_name"?: string,"p_headquarters_name": string,"p_organization_name": string,"p_organization_slug": string }; Returns: string
                           },
"bootstrap_platform_owner":
{ Args: { "p_full_name": string }; Returns: {
              "active": boolean,"full_name": string,"role": Database["public"]['Enums']["platform_operator_role"],"user_id": string
            }[]
                           },
"platform_operator_context":
{ Args: Record<PropertyKey, never>; Returns: {
              "active": boolean,"full_name": string,"role": Database["public"]['Enums']["platform_operator_role"],"user_id": string
            }[]
                           },
"set_access_context":
{ Args: { "organization_id": string,"selected_theme"?: string,"unit_id"?: string }; Returns: undefined
                           }
          }
          Enums: {
            "membership_role": "owner"|"pastor"|"admin"|"secretary"|"finance"|"leader"|"member"|"viewer","membership_status": "pending"|"active"|"suspended"|"revoked","organization_status": "active"|"trial"|"suspended"|"cancelled","platform_operator_role": "owner"|"admin"|"support"|"read_only","unit_access_level": "read"|"manage"|"admin","unit_type": "headquarters"|"campus"|"congregation"|"regional"|"branch"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            "membership_role": ["owner", "pastor", "admin", "secretary", "finance", "leader", "member", "viewer"],"membership_status": ["pending", "active", "suspended", "revoked"],"organization_status": ["active", "trial", "suspended", "cancelled"],"platform_operator_role": ["owner", "admin", "support", "read_only"],"unit_access_level": ["read", "manage", "admin"],"unit_type": ["headquarters", "campus", "congregation", "regional", "branch"]
          }
        }
} as const
