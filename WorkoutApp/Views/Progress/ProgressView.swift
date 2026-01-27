import SwiftUI
import Charts

struct ProgressTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Charts").tag(0)
                    Text("Measurements").tag(1)
                    Text("PRs").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedTab) {
                    ChartsView()
                        .tag(0)

                    MeasurementsListView()
                        .tag(1)

                    PersonalRecordsView()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Progress")
        }
    }
}

struct ChartsView: View {
    @StateObject private var viewModel = ProgressViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time range picker
                Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                    ForEach(ProgressViewModel.TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Exercise selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercise Progress")
                        .font(.headline)

                    Menu {
                        ForEach(viewModel.exercises) { exercise in
                            Button(exercise.name) {
                                Task {
                                    await viewModel.selectExercise(exercise)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(viewModel.selectedExercise?.name ?? "Select Exercise")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    if let exercise = viewModel.selectedExercise {
                        // Chart type picker
                        Picker("Chart Type", selection: $viewModel.chartType) {
                            ForEach(ProgressViewModel.ChartType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Exercise progress chart
                        if viewModel.chartData.isEmpty {
                            Text("No data for selected time range")
                                .foregroundColor(.secondary)
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                        } else {
                            Chart {
                                ForEach(viewModel.chartData, id: \.date) { point in
                                    LineMark(
                                        x: .value("Date", point.date),
                                        y: .value(viewModel.chartType.rawValue, point.value)
                                    )
                                    .foregroundStyle(Color.accentColor)

                                    PointMark(
                                        x: .value("Date", point.date),
                                        y: .value(viewModel.chartType.rawValue, point.value)
                                    )
                                    .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(height: 200)
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                        }

                        // PR info
                        if let pr = viewModel.getPR(for: exercise.id) {
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(.yellow)
                                Text("PR: \(pr.formattedWeight) x \(pr.reps)")
                                    .font(.subheadline)
                                Spacer()
                                Text(pr.achievedAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding()

                // Body weight chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Body Weight")
                        .font(.headline)

                    if viewModel.bodyWeightData.isEmpty {
                        Text("No weight data recorded")
                            .foregroundColor(.secondary)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                    } else {
                        Chart {
                            ForEach(viewModel.bodyWeightData, id: \.date) { point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.weight)
                                )
                                .foregroundStyle(Color.green)

                                AreaMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.weight)
                                )
                                .foregroundStyle(Color.green.opacity(0.1))
                            }
                        }
                        .frame(height: 150)
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            Task {
                await viewModel.loadData()
            }
        }
    }
}

struct MeasurementsListView: View {
    @StateObject private var viewModel = MeasurementViewModel()
    @State private var showingAddMeasurement = false
    @State private var selectedMeasurement: Measurement?

    var body: some View {
        Group {
            if viewModel.measurements.isEmpty {
                ContentUnavailableView(
                    "No Measurements",
                    systemImage: "ruler",
                    description: Text("Track your body measurements over time")
                )
            } else {
                List {
                    ForEach(viewModel.measurements) { measurement in
                        MeasurementRowView(measurement: measurement)
                            .onTapGesture {
                                selectedMeasurement = measurement
                            }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await viewModel.deleteMeasurement(viewModel.measurements[index])
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMeasurement = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMeasurement) {
            MeasurementFormView(viewModel: viewModel)
        }
        .sheet(item: $selectedMeasurement) { measurement in
            MeasurementDetailView(measurementId: measurement.id, viewModel: viewModel)
        }
    }
}

struct MeasurementRowView: View {
    let measurement: Measurement

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(measurement.date, style: .date)
                .font(.headline)

            HStack(spacing: 16) {
                if let weight = measurement.bodyWeight {
                    Label(String(format: "%.1f kg", weight), systemImage: "scalemass")
                }
                if let bf = measurement.bodyFat {
                    Label(String(format: "%.1f%%", bf), systemImage: "percent")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct PersonalRecordsView: View {
    @StateObject private var viewModel = ProgressViewModel()

    var body: some View {
        Group {
            if viewModel.personalRecords.isEmpty {
                ContentUnavailableView(
                    "No Personal Records",
                    systemImage: "trophy",
                    description: Text("PRs will appear here as you lift heavier")
                )
            } else {
                List(viewModel.personalRecords) { prWithExercise in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.yellow)
                            Text(prWithExercise.exercise.name)
                                .font(.headline)
                        }

                        HStack {
                            Text(prWithExercise.record.formattedWeight)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("x \(prWithExercise.record.reps)")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Est. 1RM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f kg", prWithExercise.record.estimated1RM))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }

                        Text(prWithExercise.record.achievedAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            Task {
                await viewModel.loadPersonalRecords()
            }
        }
    }
}

#Preview {
    ProgressTabView()
}
