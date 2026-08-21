import {
  BreedingWorkbench,
  type BreedingCandidate,
  type BreedingHorse,
  type PedigreeReference,
} from "@/components/breeding-workbench";
import { requireGM } from "@/lib/auth/session";

type PageProps = { searchParams: Promise<{ tab?: string }> };

export const dynamic = "force-dynamic";

export default async function AdminBreedingPage({ searchParams }: PageProps) {
  const [{ supabase }, { tab }] = await Promise.all([requireGM(), searchParams]);
  const [
    { data: candidateRows },
    { data: horseRows },
    { data: referenceRows },
    { data: gameState },
  ] = await Promise.all([
    supabase
      .from("breeding_candidates")
      .select("id, horse_id, candidate_type, is_active, notes, added_at, deactivated_at")
      .order("is_active", { ascending: false })
      .order("added_at", { ascending: false }),
    supabase
      .from("horses")
      .select("id, horse_number, foal_name, name_katakana, translated_name, sex, birth_year, life_stage, sire_name, sire_line")
      .order("horse_number"),
    supabase
      .from("pedigree_reference_horses")
      .select("id, name, translated_name, sex, sire_line, sire_name, dam_name, broodmare_sire_name, aliases, notes, is_active")
      .order("is_active", { ascending: false })
      .order("name"),
    supabase.from("game_state").select("current_wp_year").maybeSingle(),
  ]);

  const horsesById = new Map<string, BreedingHorse>(
    (horseRows ?? []).map((horse) => [horse.id, {
      id: horse.id,
      horseNumber: horse.horse_number,
      foalName: horse.foal_name,
      nameKatakana: horse.name_katakana,
      translatedName: horse.translated_name,
      sex: horse.sex,
      birthYear: horse.birth_year,
      lifeStage: horse.life_stage,
      sireName: horse.sire_name,
      sireLine: horse.sire_line,
    }]),
  );

  const candidates: BreedingCandidate[] = (candidateRows ?? []).map((candidate) => ({
    id: candidate.id,
    horseId: candidate.horse_id,
    candidateType: candidate.candidate_type as "STALLION" | "BROODMARE",
    isActive: candidate.is_active,
    notes: candidate.notes,
    addedAt: candidate.added_at,
    deactivatedAt: candidate.deactivated_at,
    horse: horsesById.get(candidate.horse_id) ?? null,
  }));

  const references: PedigreeReference[] = (referenceRows ?? []).map((reference) => ({
    id: reference.id,
    name: reference.name,
    translatedName: reference.translated_name,
    sex: reference.sex,
    sireLine: reference.sire_line,
    sireName: reference.sire_name,
    damName: reference.dam_name,
    broodmareSireName: reference.broodmare_sire_name,
    aliases: reference.aliases ?? [],
    notes: reference.notes,
    isActive: reference.is_active,
  }));

  return <BreedingWorkbench candidates={candidates} gameState={gameState ? { currentWpYear: gameState.current_wp_year } : null} initialTab={tab} references={references} />;
}
