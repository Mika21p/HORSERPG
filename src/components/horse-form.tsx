type OwnerOption = {
  id: string;
  display_name: string;
};

type HorseValues = {
  horse_number: string | number;
  birth_year: string | number;
  foal_name: string;
  name_katakana: string | null;
  translated_name: string | null;
  sex: string;
  coat_color: string;
  sire_name: string;
  sire_line: string;
  broodmare_sire_name: string;
  owner_id: string | null;
  current_jockey_name: string | null;
  current_trainer_name: string | null;
  life_stage: string;
};

type HorseFormProps = {
  action: (formData: FormData) => void | Promise<void>;
  horse?: HorseValues;
  owners: OwnerOption[];
};

const lifeStages = [
  "FOAL",
  "OWNED_FOAL",
  "TRAINING",
  "ACTIVE",
  "RETIRE_PENDING",
  "RETIRED",
  "BREEDING",
  "DISCARDED",
];

export function HorseForm({ action, horse, owners }: HorseFormProps) {
  const assignedOwner = horse?.owner_id
    ? owners.find((owner) => owner.id === horse.owner_id)
    : null;

  return (
    <form action={action} className="space-y-7">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="admin-label" htmlFor="horse_number">
          horse_number
          <input className="admin-input" defaultValue={horse?.horse_number} id="horse_number" min="1" name="horse_number" required step="1" type="number" />
        </label>
        <label className="admin-label" htmlFor="birth_year">
          birth_year
          <input className="admin-input" defaultValue={horse?.birth_year} id="birth_year" min="1" name="birth_year" required step="1" type="number" />
        </label>
        <label className="admin-label" htmlFor="foal_name">
          foal_name
          <input className="admin-input" defaultValue={horse?.foal_name} id="foal_name" name="foal_name" required />
        </label>
        <label className="admin-label" htmlFor="name_katakana">
          name_katakana
          <input className="admin-input" defaultValue={horse?.name_katakana ?? ""} id="name_katakana" name="name_katakana" />
        </label>
        <label className="admin-label" htmlFor="translated_name">
          translated_name
          <input className="admin-input" defaultValue={horse?.translated_name ?? ""} id="translated_name" name="translated_name" />
        </label>
        <label className="admin-label" htmlFor="sex">
          sex
          <select className="admin-input" defaultValue={horse?.sex ?? ""} id="sex" name="sex" required>
            <option disabled value="">选择</option>
            <option value="MALE">MALE</option>
            <option value="FEMALE">FEMALE</option>
            <option value="GELDING">GELDING</option>
          </select>
        </label>
        <label className="admin-label" htmlFor="coat_color">
          coat_color
          <input className="admin-input" defaultValue={horse?.coat_color} id="coat_color" name="coat_color" required />
        </label>
        <label className="admin-label" htmlFor="life_stage">
          life_stage
          <select className="admin-input" defaultValue={horse?.life_stage ?? "FOAL"} id="life_stage" name="life_stage" required>
            {lifeStages.map((stage) => <option key={stage} value={stage}>{stage}</option>)}
          </select>
        </label>
      </div>
      <fieldset className="grid gap-4 border-t border-stone-800 pt-6 sm:grid-cols-3">
        <legend className="pb-3 text-sm font-semibold text-amber-200">外部血统文本</legend>
        <label className="admin-label" htmlFor="sire_name">
          sire_name
          <input className="admin-input" defaultValue={horse?.sire_name} id="sire_name" name="sire_name" required />
        </label>
        <label className="admin-label" htmlFor="sire_line">
          sire_line
          <input className="admin-input" defaultValue={horse?.sire_line} id="sire_line" name="sire_line" required />
        </label>
        <label className="admin-label" htmlFor="broodmare_sire_name">
          broodmare_sire_name
          <input className="admin-input" defaultValue={horse?.broodmare_sire_name} id="broodmare_sire_name" name="broodmare_sire_name" required />
        </label>
      </fieldset>
      <fieldset className="grid gap-4 border-t border-stone-800 pt-6 sm:grid-cols-2">
        <legend className="pb-3 text-sm font-semibold text-amber-200">当前归属与人员</legend>
        {horse?.owner_id ? (
          <div className="admin-label">
            owner_id
            <p className="mt-2 rounded-lg border border-stone-800 bg-stone-950 px-3 py-2.5 text-stone-300">
              {assignedOwner?.display_name ?? "已归属 Owner"}
            </p>
            <p className="mt-2 text-xs leading-5 text-stone-500">已归属 Horse 不提供常规 Owner 转移。</p>
          </div>
        ) : (
          <label className="admin-label" htmlFor="owner_id">
            owner_id（可留空）
            <select className="admin-input" defaultValue="" id="owner_id" name="owner_id">
              <option value="">未归属</option>
              {owners.map((owner) => <option key={owner.id} value={owner.id}>{owner.display_name}</option>)}
            </select>
          </label>
        )}
        <label className="admin-label" htmlFor="current_jockey_name">
          current_jockey_name
          <input className="admin-input" defaultValue={horse?.current_jockey_name ?? ""} id="current_jockey_name" name="current_jockey_name" />
        </label>
        <label className="admin-label" htmlFor="current_trainer_name">
          current_trainer_name
          <input className="admin-input" defaultValue={horse?.current_trainer_name ?? ""} id="current_trainer_name" name="current_trainer_name" />
        </label>
      </fieldset>
      <button className="admin-button">保存 Horse</button>
    </form>
  );
}
