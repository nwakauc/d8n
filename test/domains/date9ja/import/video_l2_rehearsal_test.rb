# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    # ADR 0029 Pass 2C — the FULL isolated L2 rehearsal: sanitized metadata
    # topology + deterministic synthetic video bodies driven end-to-end through
    # Pass 1 -> Pass 2A -> Pass 2B, plus a destination verifier, rerun/idempotency,
    # interruption/recovery, a real process-kill boundary, and the adversarial
    # suite.
    #
    # SYNTHETIC ENGINEERING EVIDENCE ONLY. The sanitized snapshot does NOT
    # contain the legacy video bodies; nothing here proves anything about the
    # real videos' duration/codec/container. The happy-path corpus mirrors the
    # census METADATA shape (35 records, 26 video/mp4 + 9 video/quicktime) so the
    # migration machinery is exercised against the real topology.
    #
    # Slow (~2-3 min): it renders 35 videos with ffmpeg and runs real
    # ffprobe/processing. Run explicitly.
    class VideoL2RehearsalTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper
      include ActiveSupport::Testing::TimeHelpers

      SVM = Date9ja::Snapshot::SyntheticVideoMedia

      # Minimal in-memory stand-in for the media_v3 / parent snapshot connections
      # (self-contained so the file runs in its own parallel process).
      class FakeConn
        COLS = %w[id key filename content_type metadata service_name byte_size checksum created_at].freeze
        ATT_COLS = %w[id name record_type record_id blob_id created_at].freeze
        FakeResult = Struct.new(:to_a)

        def initialize(blobs:)
          @src = blobs
          @blobs = blobs.map { |b| COLS.to_h { |c| [ c, b.fetch(c, dflt(c, b)) ] } }
          @attachments = @blobs.each_with_index.map do |b, i|
            ATT_COLS.to_h { |c| [ c, { "id" => (500 + i).to_s, "name" => "video", "record_type" => "ProfileVideo",
              "record_id" => (i + 1).to_s, "blob_id" => b["id"], "created_at" => "2024-01-01 00:00:00" }[c] ] }
          end
          @counts = { "users" => 35, "profiles" => 35, "profile_videos" => @blobs.size,
                      "active_storage_attachments" => @attachments.size }
        end
        attr_reader :blobs

        def exec_query(sql, *)
          rows =
            if sql.include?("information_schema.columns") && sql.include?("active_storage_attachments")
              ATT_COLS.map { |c| { "column_name" => c } }
            elsif sql.include?("information_schema.columns")
              COLS.map { |c| { "column_name" => c } }
            elsif sql.include?("to_regclass")
              t = sql[/public\.([a-z_]+)/, 1]
              [ { "t" => (@counts.key?(t) ? t : nil) } ]
            elsif sql.include?("SELECT COUNT(*) AS n FROM ")
              [ { "n" => @counts.fetch(sql[/FROM (\w+)/, 1], 0) } ]
            elsif sql.include?("FROM profile_videos")
              @blobs.each_with_index.map do |b, i|
                { "video_id" => (i + 1).to_s, "user_id" => (100 + i).to_s, "moderation_status" => "0",
                  "attachment_id" => (500 + i).to_s, "blob_id" => b["id"],
                  "key" => b["key"], "content_type" => b["content_type"], "service_name" => b["service_name"] }
              end
            elsif sql.include?("FROM active_storage_attachments") && sql.include?("WHERE a.record_type")
              @blobs.map { |b| { "blob_id" => b["id"] } }
            elsif sql.include?("FROM active_storage_attachments") && !sql.include?("JOIN")
              @attachments
            elsif sql.include?("WHERE id IN")
              ids = sql[/WHERE id IN \(([^)]*)\)/, 1].split(",").map(&:strip)
              @blobs.select { |b| ids.include?(b["id"].to_s) }
            elsif sql.include?("FROM active_storage_blobs") && !sql.include?("JOIN")
              @blobs
            else
              @blobs.map { |b| b.slice("id", "key", "content_type", "service_name") }
            end
          FakeResult.new(rows)
        end

        def exec_update(sql, *)
          id = sql[/WHERE id = (\d+)/, 1].to_i
          size = sql[/byte_size = (\d+)/, 1].to_i
          checksum = sql[/checksum = '([^']+)'/, 1]
          [ @blobs, @src ].each do |set|
            row = set.find { |b| b["id"].to_i == id }
            next unless row

            row["byte_size"] = size
            row["checksum"] = checksum
          end
          1
        end

        def transaction = yield
        def quote(v) = "'#{v}'"

        def dflt(c, b)
          { "filename" => "v-#{b['id']}.mp4", "metadata" => "{}",
            "created_at" => "2024-01-01 00:00:00", "byte_size" => 0, "checksum" => "" }[c]
        end
      end

      # The sanitized census (RECONCILIATION.md): 35 ProfileVideo records,
      # 26 video/mp4 + 9 video/quicktime.
      CENSUS_MP4 = 26
      CENSUS_MOV = 9
      CENSUS_TOTAL = CENSUS_MP4 + CENSUS_MOV

      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password])
        @run = SecureRandom.hex(4)
        @blob_base = rand(200_000..800_000) * 1_000 # numeric, unique per run (real AS blob ids are integers)
        @seed = "l2-#{@run}"
        @corpus_dir = Dir.mktmpdir("video-l2-corpus")
      end

      teardown { FileUtils.remove_entry(@corpus_dir) if @corpus_dir && File.directory?(@corpus_dir) }

      # --- corpus + topology --------------------------------------------

      # Blob rows for the FakeConn generator (and, after patching, the source).
      def census_blob_rows(count_mp4: CENSUS_MP4, count_mov: CENSUS_MOV)
        rows = []
        (count_mp4 + count_mov).times do |i|
          ct = i < count_mp4 ? "video/mp4" : "video/quicktime"
          rows << { "id" => (@blob_base + i).to_s, "key" => "legacy/#{@run}/#{format('%03d', i)}",
            "content_type" => ct, "service_name" => "cloudflare", "byte_size" => 0, "checksum" => "" }
        end
        rows
      end

      def build_corpus(blob_rows, patch: true, dir: @corpus_dir)
        result = SVM::Generator.new(connection: FakeConn.new(blobs: blob_rows), corpus_dir: dir,
          seed: @seed, patch_metadata: patch).call
        [ result, JSON.parse(File.read(result.manifest_path)) ]
      end

      # Wire the patched blob metadata into a Snapshot::VideoSource + locator +
      # a LocalCorpusReader over the generated bytes.
      def source_graph(blob_rows, owners:)
        videos = []
        attachments = []
        blobs = []
        locator_rows = {}
        blob_rows.each_with_index do |b, i|
          vid = "#{@run}v#{i}"
          aid = "#{@run}a#{i}"
          owner = owners.fetch(i % owners.size)
          videos << { "id" => vid, "user_id" => owner, "duration_seconds" => nil,
            "moderation_status" => [ 0, 1, 2 ][i % 3],
            "created_at" => Time.utc(2024, 1, 1), "reviewed_at" => nil }
          attachments << { "id" => aid, "name" => "video", "record_type" => "ProfileVideo",
            "record_id" => vid, "blob_id" => b["id"] }
          blobs << { "id" => b["id"], "byte_size" => b["byte_size"], "checksum" => b["checksum"],
            "content_type" => b["content_type"] }
          locator_rows[b["id"]] = { key: b["key"], service_name: "cloudflare" }
        end
        {
          source: -> { Snapshot::VideoSource.new(videos:, attachments:, blobs:) },
          locator: Snapshot::VideoLocatorSource.new(rows: locator_rows),
          reader: Date9ja::Storage::LocalCorpusReader.new(corpus_dir: @corpus_dir),
          video_ids: videos.map { |v| v["id"] }
        }
      end

      def import_owner(sid, status: :active)
        existing = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile", source_id: sid)
        return existing if existing

        user = User.create!
        m = BrandMembership.create!(user:, brand: @brand, status:)
        profile = Profile.create!(user:, brand: @brand, brand_membership: m,
          display_name: "P#{user.id}", birthdate: 27.years.ago.to_date, gender: "woman", status: :draft)
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "profile",
          source_id: sid, destination: profile, importer_version: "date9ja-identity-v1", brand: @brand)
        profile
      end

      # =================================================================
      # THE FULL HAPPY-PATH REHEARSAL — one method, one corpus render.
      # =================================================================

      test "L2: 35-record census -> Pass 1 -> Pass 2A -> Pass 2B -> destination verify -> rerun" do
        blob_rows = census_blob_rows
        gen_result, manifest = build_corpus(blob_rows)

        # ---- corpus facts (derived from execution) -------------------
        assert_equal CENSUS_TOTAL, gen_result.object_count
        assert_equal({ "video/mp4" => CENSUS_MP4, "video/quicktime" => CENSUS_MOV }, gen_result.content_type_counts)
        assert_equal CENSUS_TOTAL, gen_result.patched_rows
        fingerprint = gen_result.manifest_fingerprint
        assert_match(/\A[0-9a-f]{64}\z/, fingerprint)

        # ---- determinism: a second clean generation is byte-identical
        second_dir = Dir.mktmpdir("video-l2-corpus-2")
        begin
          r2, m2 = build_corpus(Marshal.load(Marshal.dump(blob_rows)), patch: false, dir: second_dir)
          assert_equal fingerprint, r2.manifest_fingerprint, "generator is not deterministic"
          m2["objects"].each do |o|
            a = File.join(@corpus_dir, "objects", o["source_key"])
            b = File.join(second_dir, "objects", o["source_key"])
            assert_equal File.binread(a), File.binread(b), "#{o['source_key']} differs across runs"
          end
        ensure
          FileUtils.remove_entry(second_dir)
        end

        # ---- independent corpus verifier ----------------------------
        v3 = FakeConn.new(blobs: blob_rows) # already patched by build_corpus
        parent = FakeConn.new(blobs: blob_rows.map { |b| b.merge("byte_size" => 0, "checksum" => "") })
        vres = SVM::Verifier.new(
          media_v3_connection: v3, parent_connection: parent, corpus_dir: @corpus_dir,
          manifest:, expected_object_count: CENSUS_TOTAL
        ).call
        assert vres.ok?, "corpus verifier failed: #{vres.failures.map { |c| "#{c[:check]}:#{c[:detail]}" }.join(', ')}"

        # ---- topology: 35 owners, 1 video each ----------------------
        owners = CENSUS_TOTAL.times.map { |i| "#{@run}u#{i}" }
        owners.each { |sid| import_owner(sid) }
        g = source_graph(blob_rows, owners:)

        # ---- Pass 1 -----------------------------------------------
        p1 = VideoPreflight.call(brand: @brand, source: g[:source].call).reconciliation.to_h
        assert p1["balanced"]
        assert_equal CENSUS_TOTAL, p1["videos_considered"]
        assert_equal CENSUS_TOTAL, p1.dig("dispositions", "preflighted")
        assert_equal CENSUS_TOTAL, p1.dig("created", "media_object_refs_created")
        assert_equal CENSUS_TOTAL,
          %w[moderation_pending moderation_approved moderation_rejected].sum { |m| p1.dig("measures", m) }
        assert_equal CENSUS_TOTAL, Migration::MediaObjectRef.where(source_system: "date9ja").count

        # ---- Pass 2A (stage: :adopt) — derive counts from execution
        a = VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
          source_reader: g[:reader], stage: :adopt).reconciliation.to_h
        assert a["balanced"]
        assert_equal CENSUS_TOTAL, a["videos_considered"]
        assert_equal CENSUS_TOTAL, a.dig("dispositions", "destination_adopted")
        assert_equal CENSUS_TOTAL, a.dig("measures", "duration_derived")
        assert_equal CENSUS_TOTAL, a.dig("measures", "duration_within_limit")
        assert_equal CENSUS_MP4, a.dig("measures", "content_type_mp4")
        assert_equal CENSUS_MOV, a.dig("measures", "content_type_quicktime")
        assert_equal 0, a.dig("dispositions", "quarantined")
        assert_equal 0, ProfileVideo.count, "Pass 2A creates no ProfileVideo"
        adopted_blobs = ActiveStorage::Blob.where("key LIKE ?", "migrations/media/v3/date9ja/profile_video_original/%").count
        assert_equal CENSUS_TOTAL, adopted_blobs

        # ---- Pass 2B (stage: :domain) — interruption window A: adopted, no PV
        b = perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain).reconciliation.to_h
        end
        assert b["balanced"]
        assert_equal CENSUS_TOTAL, b["videos_considered"]
        assert_equal CENSUS_TOTAL, b.dig("dispositions", "ready"), b["reason_codes"].inspect
        assert_equal CENSUS_TOTAL, b.dig("measures", "profile_videos_created")
        assert_equal CENSUS_TOTAL, b.dig("measures", "reference_map_bindings_created")
        assert_equal CENSUS_TOTAL, b.dig("measures", "playback_validated")
        assert_equal CENSUS_TOTAL, b.dig("measures", "poster_validated")
        assert_equal CENSUS_TOTAL, b.dig("measures", "originals_purged")
        assert_equal "domain", b["stage"]
        refute b["dispositions"].key?("transferred")

        # ---- independent destination verifier -----------------------
        verify_destination!(g[:video_ids], blob_rows, owners)

        # ---- rerun / idempotency ----------------------------------
        counts_before = destination_counts
        r = perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain).reconciliation.to_h
        end
        assert_equal CENSUS_TOTAL, r.dig("dispositions", "already_ready")
        assert_equal 0, r.dig("dispositions", "ready")
        assert_equal 0, r.dig("measures", "processing_succeeded")
        assert_equal counts_before, destination_counts, "rerun changed destination state"
        # raw originals were purged and must NOT be recreated
        assert_equal 0, ActiveStorage::Attachment.where(record_type: "ProfileVideo", name: "video").count

        # record the fingerprint for the evidence doc
        puts "[L2] corpus_fingerprint=#{fingerprint} objects=#{CENSUS_TOTAL} mp4=#{CENSUS_MP4} mov=#{CENSUS_MOV}"
      end

      # A STABLE, documentable corpus fingerprint for a fixed census-shaped
      # blob-id set + fixed seed (no ActiveStorage — corpus files only). The
      # canonical fingerprint for the real `date9ja_snapshot_sanitized_media_v3`
      # artifact is produced by the operator `date9ja:build_video_media_v3` run
      # against the real 35 source blob ids.
      DOC_SEED = "date9ja-video-media-v3-doc-2026-09-04"
      DOC_FINGERPRINT = "5fbcc9dac1d7334859c5753b3c5b347589898af0ce3302e15cc117366433c378"

      test "L2: fixed census-shaped corpus has a stable, reproducible fingerprint" do
        rows = 35.times.map do |i|
          { "id" => (i + 1).to_s, "key" => "snapshot/#{i + 1}/#{format('%032x', i)}",
            "content_type" => i < 26 ? "video/mp4" : "video/quicktime",
            "service_name" => "cloudflare", "byte_size" => 0, "checksum" => "" }
        end
        d1 = Dir.mktmpdir("fp1")
        d2 = Dir.mktmpdir("fp2")
        begin
          r1 = SVM::Generator.new(connection: FakeConn.new(blobs: rows), corpus_dir: d1, seed: DOC_SEED, patch_metadata: false).call
          r2 = SVM::Generator.new(connection: FakeConn.new(blobs: Marshal.load(Marshal.dump(rows))),
            corpus_dir: d2, seed: DOC_SEED, patch_metadata: false).call

          assert_equal r1.manifest_fingerprint, r2.manifest_fingerprint, "not reproducible across two clean generations"
          m1 = JSON.parse(File.read(r1.manifest_path))
          m1["objects"].each do |o|
            assert_equal File.binread(File.join(d1, "objects", o["source_key"])),
              File.binread(File.join(d2, "objects", o["source_key"])), "#{o['source_key']} differs"
          end
          # Regression-lock the fingerprint (update DOC_FINGERPRINT only with a
          # deliberate generator change — see VIDEO-L2.md).
          assert_equal DOC_FINGERPRINT, r1.manifest_fingerprint if DOC_FINGERPRINT.present?
          puts "[L2] DOC_FINGERPRINT=#{r1.manifest_fingerprint}"
        ensure
          FileUtils.remove_entry(d1)
          FileUtils.remove_entry(d2)
        end
      end

      # --- destination verifier (independent of reconciliation) --------

      def destination_counts
        {
          profile_videos: ProfileVideo.count,
          kept_ready: ProfileVideo.kept.processing_ready.count,
          bindings: LegacyReference.where(source_system: "date9ja", source_entity: "profile_video").count,
          playback: ActiveStorage::Attachment.where(record_type: "ProfileVideo", name: "playback").count,
          poster: ActiveStorage::Attachment.where(record_type: "ProfileVideo", name: "poster").count,
          raw: ActiveStorage::Attachment.where(record_type: "ProfileVideo", name: "video").count
        }
      end

      def verify_destination!(video_ids, blob_rows, owners)
        assert_equal video_ids.size, ProfileVideo.count, "exactly one ProfileVideo per source video"
        assert_equal video_ids.size, LegacyReference.where(source_system: "date9ja", source_entity: "profile_video").count

        video_ids.each_with_index do |vid, i|
          ref = Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: "profile_video", source_id: vid)
          assert ref, "binding resolves exactly once for #{vid}"
          assert_equal "ProfileVideo", ref.destination_type
          pv = ref.destination
          assert pv.kept?
          assert_equal @brand.id, pv.brand_id, "no cross-brand binding"
          expected_owner = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile",
            source_id: owners.fetch(i % owners.size))
          assert_equal expected_owner.id, pv.profile_id
          assert_equal expected_owner.user_id, pv.user_id
          assert pv.processing_ready?
          assert pv.playback.attached?
          assert pv.poster.attached?
          assert_not pv.video.attached?, "raw purged"

          original_key = Migration::MediaTransfer::CanonicalKey.final_key(
            Migration::MediaTransfer::CanonicalKey::Identity.new(
              source_system: "date9ja", source_blob_id: blob_rows[i]["id"],
              source_attachment_id: "#{@run}a#{i}", destination_purpose: "profile_video_original",
              destination_brand: "date9ja", canonical_content_type: blob_rows[i]["content_type"]
            )
          )
          assert_equal Media::ObjectKey.profile_video_playback(original_key), pv.playback.blob.key
          assert_equal Media::ObjectKey.profile_video_poster(original_key), pv.poster.blob.key
          assert Migration::MediaTransfer.valid_accepted_playback?(
            video: pv, expected_playback_key: pv.playback.blob.key, expected_poster_key: pv.poster.blob.key,
            expected_service: Media::StorageResolver.service_name(brand: @brand).to_s
          ), "remote playback+poster validate for #{vid}"

          # moderation preserved: source status i%3 -> pending/approved/rejected
          case i % 3
          when 0 then assert pv.pending_review? && pv.visible?
          when 1 then assert pv.approved? && pv.visible?
          when 2 then assert pv.rejected? && pv.hidden?
          end
        end

        # no unexpected rows
        assert_equal video_ids.size, ProfileVideo.where(brand: @brand).count
        assert_equal 0, ProfileVideo.where.not(brand: @brand).count
      end

      # =================================================================
      # INTERRUPTION / RECOVERY (small corpus, targeted windows)
      # =================================================================

      def small_setup(n: 2)
        blob_rows = census_blob_rows(count_mp4: n, count_mov: 0)
        build_corpus(blob_rows)
        owners = n.times.map { |i| "#{@run}u#{i}" }
        owners.each { |sid| import_owner(sid) }
        g = source_graph(blob_rows, owners:)
        VideoPreflight.call(brand: @brand, source: g[:source].call)
        [ blob_rows, g ]
      end

      test "L2 interruption B/E: crash during processing -> restart resumes to ready, no rebuild" do
        _rows, g = small_setup(n: 1)

        stub_method(Media::VideoProcessor, :call, ->(_b) { raise Media::VideoProcessor::TimedOut, "crash" }) do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain) rescue nil
        end
        clear_enqueued_jobs # drop the leftover retry so the restart genuinely resumes
        vid = g[:video_ids].first
        pv = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile_video", source_id: vid)
        assert pv, "binding committed before the crash"
        assert_not pv.processing_ready?
        assert pv.video.attached?, "raw still present (never reached ready)"
        pv_count = ProfileVideo.count

        recon = perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain).reconciliation
        end
        assert_equal 1, recon.count(:ready), "the restart drives it to ready"
        assert_equal pv_count, ProfileVideo.count, "resumed, not rebuilt"
        assert pv.reload.processing_ready?
      end

      test "L2 interruption C: a stale processing claim (bound, not-ready, raw present) is reclaimed to ready" do
        _rows, g = small_setup(n: 1)
        # Bind + processing crashes -> bound, not ready, raw still attached.
        stub_method(Media::VideoProcessor, :call, ->(_b) { raise Media::VideoProcessor::TimedOut, "crash" }) do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain) rescue nil
        end
        vid = g[:video_ids].first
        pv = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile_video", source_id: vid)
        assert pv.video.attached?
        pv.update_columns(processing_state: ProfileVideo.processing_states[:processing],
          processing_started_at: (ProfileVideo::STALE_PROCESSING_AFTER + 5.minutes).ago,
          processing_claim_token: SecureRandom.uuid)
        assert pv.reload.processing_claim_stale?

        recon = perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain).reconciliation
        end
        assert_equal 1, recon.measure(:processing_stale_reclaims)
        assert_equal 1, recon.count(:ready)
        assert pv.reload.processing_ready?
      end

      test "L2 interruption F/G: ready video with raw purged, restart -> already_ready, raw not recreated" do
        _rows, g = small_setup(n: 1)
        perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain)
        end
        vid = g[:video_ids].first
        pv = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile_video", source_id: vid)
        assert_not pv.video.attached?

        recon = perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain).reconciliation
        end
        assert_equal 1, recon.count(:already_ready)
        assert_not pv.reload.video.attached?, "raw must not be recreated"
      end

      # =================================================================
      # PROCESS-KILL BOUNDARY EVIDENCE
      # =================================================================
      #
      # A true SIGKILL of a forked processing worker is NOT safely automatable
      # here: minitest wraps each test in a rolled-back transaction, so a forked
      # child shares the parent's uncommitted transactional connection and a
      # kill mid-savepoint corrupts the shared fixture state. This test instead
      # reproduces the EXACT durable on-disk state a SIGKILLed worker leaves —
      # `processing` + a claim token, with no FINALIZE/FAILURE having run (no
      # rescue, no ensure) — and proves deterministic recovery. The real
      # forked-worker SIGKILL rehearsal is part of the operator L2 run against
      # `date9ja_snapshot_sanitized_media_v3` (see VIDEO-L2.md).

      test "L2 process-kill boundary: a killed worker's durable claim is reclaimed and recovered deterministically" do
        _rows, g = small_setup(n: 1)

        # Phase A + B commit (bind), processing crashes before finalizing.
        stub_method(Media::VideoProcessor, :call, ->(_b) { raise Media::VideoProcessor::TimedOut, "killed" }) do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain) rescue nil
        end
        vid = g[:video_ids].first
        pv = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile_video", source_id: vid)
        assert pv, "binding committed before the kill"

        assert pv.video.attached?, "raw still present (never reached ready)"

        # Exactly the durable state a SIGKILL leaves: CLAIM ran (processing +
        # token, started_at), nothing after it (no FINALIZE, no FAILURE, no
        # ensure). The ABA guard on this token is proven in
        # Media::ProcessProfileVideoJobClaimTest — here we prove recovery.
        killed_token = SecureRandom.uuid
        pv.update_columns(processing_state: ProfileVideo.processing_states[:processing],
          processing_started_at: (ProfileVideo::STALE_PROCESSING_AFTER + 2.minutes).ago,
          processing_claim_token: killed_token)
        assert pv.reload.processing_claim_stale?

        # Operator restart: the migration re-runs; the stale claim is reclaimed
        # and the video reaches ready deterministically.
        recon = perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
            source_reader: g[:reader], stage: :domain).reconciliation
        end
        assert_equal 1, recon.measure(:processing_stale_reclaims)
        assert_equal 1, recon.count(:ready)
        pv.reload
        assert pv.processing_ready?
        assert pv.playback.attached? && pv.poster.attached?
        assert_not pv.video.attached?
        assert_nil pv.processing_claim_token
        refute_equal killed_token, pv.processing_claim_token
      end

      # =================================================================
      # ADVERSARIAL SUITE (separate from the 35-record census)
      # =================================================================

      def adversarial_run(bytes:, content_type: "video/mp4", byte_size: nil, checksum: nil, stage: :domain)
        blob_id = "#{@run}adv"
        aid = "#{@run}advA"
        vid = "#{@run}advV"
        key = "legacy/#{@run}/adv"
        FileUtils.mkdir_p(File.join(@corpus_dir, "objects", "legacy", @run))
        File.binwrite(File.join(@corpus_dir, "objects", key), bytes)

        import_owner("#{@run}advU")
        videos = [ { "id" => vid, "user_id" => "#{@run}advU", "duration_seconds" => nil,
          "moderation_status" => 1, "created_at" => Time.utc(2024, 1, 1), "reviewed_at" => nil } ]
        atts = [ { "id" => aid, "name" => "video", "record_type" => "ProfileVideo", "record_id" => vid, "blob_id" => blob_id } ]
        blobs = [ { "id" => blob_id, "byte_size" => byte_size || bytes.bytesize,
          "checksum" => checksum || Digest::MD5.base64digest(bytes), "content_type" => content_type } ]
        src = -> { Snapshot::VideoSource.new(videos:, attachments: atts, blobs:) }
        loc = Snapshot::VideoLocatorSource.new(rows: { blob_id => { key:, service_name: "cloudflare" } })
        reader = Date9ja::Storage::LocalCorpusReader.new(corpus_dir: @corpus_dir)

        VideoPreflight.call(brand: @brand, source: src.call)
        recon = perform_enqueued_jobs do
          VideoTransfer.call(brand: @brand, source: src.call, locator: loc, source_reader: reader, stage:).reconciliation
        end
        [ recon, vid ]
      end

      test "adversarial: valid video > 60s -> quarantined/duration_over_limit, no domain artifacts" do
        recon, vid = adversarial_run(bytes: SVM.render_over_limit(seconds: 64))
        assert_equal 1, recon.count(:quarantined)
        assert_equal 1, recon.reason_count("duration_over_limit")
        assert_equal 0, ProfileVideo.count
        assert_nil Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: "profile_video", source_id: vid)
      end

      test "adversarial: unreadable duration -> quarantined/duration_unreadable, no domain artifacts" do
        recon, = adversarial_run(bytes: build_test_mp4_bytes) # valid container, no ffprobe duration
        assert_equal 1, recon.count(:quarantined)
        assert_equal 1, recon.reason_count("duration_unreadable")
        assert_equal 0, ProfileVideo.count
      end

      test "adversarial: malformed/truncated container -> validation_failed" do
        good = SVM.render(source_blob_id: "x", canonical_content_type: "video/mp4", seed: @seed)
        recon, = adversarial_run(bytes: good[0, good.bytesize - 80])
        assert_equal 1, recon.count(:validation_failed)
        assert_equal 1, recon.reason_count("malformed_container")
      end

      test "adversarial: spoofed type (image bytes as video/mp4) -> validation_failed" do
        recon, = adversarial_run(bytes: build_test_jpeg_bytes)
        assert_equal 1, recon.count(:validation_failed)
        assert_equal 1, recon.reason_count("not_a_video")
      end

      test "adversarial: checksum drift -> source_changed" do
        good = SVM.render(source_blob_id: "x", canonical_content_type: "video/mp4", seed: @seed)
        recon, = adversarial_run(bytes: good, checksum: Digest::MD5.base64digest("other"))
        assert_equal 1, recon.count(:source_changed)
        assert_equal 1, recon.reason_count("source_checksum_mismatch")
      end

      test "adversarial: byte-size drift -> source_changed" do
        good = SVM.render(source_blob_id: "x", canonical_content_type: "video/mp4", seed: @seed)
        recon, = adversarial_run(bytes: good, byte_size: good.bytesize + 17)
        assert_equal 1, recon.count(:source_changed)
        assert_equal 1, recon.reason_count("source_size_mismatch")
      end

      test "adversarial: content-type drift (declared mp4, actual mov) -> source_changed" do
        mov = SVM.render(source_blob_id: "x", canonical_content_type: "video/quicktime", seed: @seed)
        recon, = adversarial_run(bytes: mov, content_type: "video/mp4")
        assert_equal 1, recon.count(:source_changed)
        assert_equal 1, recon.reason_count("content_type_drift")
      end

      test "adversarial: destination collision -> binding_conflict, fail closed" do
        good = SVM.render(source_blob_id: "x", canonical_content_type: "video/mp4", seed: @seed)
        recon, = adversarial_run(bytes: good, stage: :adopt)
        assert_equal 1, recon.count(:destination_adopted)
        # tamper the adopted object, rerun
        blob = ActiveStorage::Blob.where("key LIKE ?", "migrations/media/v3/date9ja/profile_video_original/%").last
        blob.service.upload(blob.key, StringIO.new(SVM.render(source_blob_id: "y", canonical_content_type: "video/mp4", seed: @seed)))
        recon2, = adversarial_run(bytes: good, stage: :adopt)
        assert_equal 1, recon2.count(:binding_conflict)
        assert_equal 1, recon2.reason_count("destination_collision")
      end

      test "adversarial: remote orphan -> binding_conflict, never adopted" do
        good = SVM.render(source_blob_id: "x", canonical_content_type: "video/mp4", seed: @seed)
        blob_id = "#{@run}orph"
        aid = "#{@run}orphA"
        vid = "#{@run}orphV"
        key = "legacy/#{@run}/orph"
        FileUtils.mkdir_p(File.dirname(File.join(@corpus_dir, "objects", key)))
        File.binwrite(File.join(@corpus_dir, "objects", key), good)
        import_owner("#{@run}orphU")

        identity = Migration::MediaTransfer::CanonicalKey::Identity.new(
          source_system: "date9ja", source_blob_id: blob_id, source_attachment_id: aid,
          destination_purpose: "profile_video_original", destination_brand: "date9ja",
          canonical_content_type: "video/mp4"
        )
        orphan_key = Migration::MediaTransfer::CanonicalKey.final_key(identity)
        ActiveStorage::Blob.service.upload(orphan_key, StringIO.new(good))

        videos = [ { "id" => vid, "user_id" => "#{@run}orphU", "duration_seconds" => nil,
          "moderation_status" => 1, "created_at" => Time.utc(2024, 1, 1), "reviewed_at" => nil } ]
        atts = [ { "id" => aid, "name" => "video", "record_type" => "ProfileVideo", "record_id" => vid, "blob_id" => blob_id } ]
        blobs = [ { "id" => blob_id, "byte_size" => good.bytesize, "checksum" => Digest::MD5.base64digest(good), "content_type" => "video/mp4" } ]
        src = -> { Snapshot::VideoSource.new(videos:, attachments: atts, blobs:) }
        loc = Snapshot::VideoLocatorSource.new(rows: { blob_id => { key:, service_name: "cloudflare" } })
        reader = Date9ja::Storage::LocalCorpusReader.new(corpus_dir: @corpus_dir)
        VideoPreflight.call(brand: @brand, source: src.call)
        recon = VideoTransfer.call(brand: @brand, source: src.call, locator: loc, source_reader: reader, stage: :domain).reconciliation

        assert_equal 1, recon.count(:binding_conflict)
        assert_equal 1, recon.reason_count("remote_orphan")
        assert_nil ActiveStorage::Blob.find_by(key: orphan_key)
        assert_equal 0, ProfileVideo.count
      end

      test "adversarial: invalid playback rendition -> fail closed, never ready (review Finding 1)" do
        _rows, g = small_setup(n: 1)
        bogus = Media::VideoProcessor::Result.new(
          rendition_bytes: "not a container".b, transcoded: true,
          poster_bytes: build_test_jpeg_bytes, width: 64, height: 64, duration_seconds: 3.0
        )
        recon = stub_method(Media::VideoProcessor, :call, ->(_b) { bogus }) do
          perform_enqueued_jobs do
            VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
              source_reader: g[:reader], stage: :domain).reconciliation
          end
        end
        assert_equal 0, recon.count(:ready)
        assert_equal 1, recon.count(:processing_failed) + recon.count(:derivative_validation_failed)
        vid = g[:video_ids].first
        pv = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile_video", source_id: vid)
        assert_not pv.processing_ready?, "the job never persists ready with an invalid playback"
        assert pv.video.attached?, "raw not purged"
        assert_not pv.playback.attached?
      end

      test "adversarial: tampered poster derivative -> not ready" do
        _rows, g = small_setup(n: 1)
        good_playback = SVM.render(source_blob_id: "p", canonical_content_type: "video/mp4", seed: @seed)
        bogus = Media::VideoProcessor::Result.new(
          rendition_bytes: good_playback, transcoded: false,
          poster_bytes: "not a jpeg".b, width: 64, height: 64, duration_seconds: 3.0
        )
        recon = stub_method(Media::VideoProcessor, :call, ->(_b) { bogus }) do
          perform_enqueued_jobs do
            VideoTransfer.call(brand: @brand, source: g[:source].call, locator: g[:locator],
              source_reader: g[:reader], stage: :domain).reconciliation
          end
        end
        assert_equal 0, recon.count(:ready)
      end
    end
  end
end
