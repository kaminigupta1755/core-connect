import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Edit } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { bossDispatch } from "@/hooks/boss-core";

interface LegalDoc {
  id: string;
  title: string;
  doc_type: string | null;
  version: string | null;
  status: string | null;
  region: string[] | null;
  created_at: string | null;
}

const LegalPoliciesTerms = () => {
  const [docs, setDocs] = useState<LegalDoc[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase
        .from("legal_documents")
        .select("id,title,doc_type,version,status,region,created_at")
        .order("created_at", { ascending: false });
      if (!alive) return;
      setDocs((data ?? []) as LegalDoc[]);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  const proposeUpdate = async (doc: LegalDoc) => {
    const { error } = await bossDispatch.requestApproval({
      module: "legal",
      actionKey: "legal.policy.update",
      title: `Update: ${doc.title}`,
      description: `Proposed update for ${doc.title} (v${doc.version ?? "?"})`,
      payload: { document_id: doc.id, current_version: doc.version },
    });
    if (error) toast.error(error.message);
    else toast.success("Update request sent to Boss");
  };

  return (
    <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="space-y-6">
      <h2 className="text-xl font-semibold text-white">Policies & Terms</h2>
      <Card className="bg-slate-900/50 border-slate-700/50">
        <CardHeader><CardTitle className="text-amber-400">All Legal Documents</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <p className="text-slate-400 text-sm py-6 text-center">Loading…</p>
          ) : docs.length === 0 ? (
            <p className="text-slate-400 text-sm py-10 text-center border border-dashed border-slate-700 rounded-lg">
              No legal documents yet.
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="border-slate-700">
                  <TableHead className="text-slate-400">Document</TableHead>
                  <TableHead className="text-slate-400">Type</TableHead>
                  <TableHead className="text-slate-400">Version</TableHead>
                  <TableHead className="text-slate-400">Region</TableHead>
                  <TableHead className="text-slate-400">Status</TableHead>
                  <TableHead className="text-slate-400">Updated</TableHead>
                  <TableHead className="text-slate-400">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {docs.map((d) => (
                  <TableRow key={d.id} className="border-slate-700/50">
                    <TableCell className="text-white font-medium">{d.title}</TableCell>
                    <TableCell className="text-slate-300">{d.doc_type ?? "—"}</TableCell>
                    <TableCell className="text-slate-300">v{d.version ?? "—"}</TableCell>
                    <TableCell className="text-slate-300">{d.region ?? "—"}</TableCell>
                    <TableCell><Badge>{d.status ?? "—"}</Badge></TableCell>
                    <TableCell className="text-slate-400 text-xs">{d.created_at ? new Date(d.created_at).toLocaleDateString() : "—"}</TableCell>
                    <TableCell>
                      <Button size="sm" variant="ghost" onClick={() => proposeUpdate(d)}>
                        <Edit className="h-4 w-4 text-amber-400" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </motion.div>
  );
};

export default LegalPoliciesTerms;
