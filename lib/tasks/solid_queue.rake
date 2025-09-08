namespace :solid_queue do
  desc "Display SolidQueue process heartbeats and pending jobs by queue"
  task health: :environment do
    puts "Processes:" 
    SolidQueue::Process.all.each do |proc|
      puts " - #{proc.id} last_heartbeat: #{proc.last_heartbeat_at}"
    end

    puts "Pending jobs:"
    SolidQueue::Job.group(:queue_name).count.each do |queue, count|
      puts " - #{queue}: #{count}"
    end
  end
end

